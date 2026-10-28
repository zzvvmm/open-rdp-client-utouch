#include "RdpBridge.h"

#include <QAudioFormat>
#include <QClipboard>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QRegularExpression>
#include <cstdio>
#include <mutex>

namespace {
QtMessageHandler previousMessageHandler = nullptr;
std::once_flag reportingHandlerInstalled;

void reportQtMessage(QtMsgType type, const QMessageLogContext &context, const QString &message) {
    thread_local bool reporting = false;
    if (!reporting) {
        reporting = true;
        const char *code = nullptr;
        if (type == QtCriticalMsg || type == QtFatalMsg) code = "qt_critical";
        else if (type == QtWarningMsg) {
            if (message.contains(QStringLiteral("ReferenceError:"))) code = "qml_reference";
            else if (message.contains(QStringLiteral("TypeError:"))) code = "qml_type";
            else if (message.contains(QStringLiteral("Binding loop detected"))) code = "qml_binding";
            else if (message.contains(QStringLiteral("SyntaxError:"))) code = "qml_load";
        }
        if (code) {
            QString source = QString::fromUtf8(context.file ? context.file : "");
            unsigned int line = context.line > 0 ? context.line : 0;
            static const QRegularExpression qmlLocation(QStringLiteral("^(qrc:/qml/[A-Za-z0-9_/.-]+\\.qml):(\\d+):"));
            const auto location = qmlLocation.match(message);
            if (location.hasMatch()) { source = location.captured(1); line = location.captured(2).toUInt(); }
            const auto file = source.toUtf8();
            rdp_report_ui_error(code, file.constData(), line, type == QtFatalMsg ? 1 : 0);
        }
        reporting = false;
    }
    if (previousMessageHandler) previousMessageHandler(type, context, message);
    else std::fprintf(stderr, "%s\n", message.toLocal8Bit().constData());
}
}

RdpBridge::RdpBridge(QObject *parent)
    : QObject(parent) {
    m_handle = rdp_app_create(&RdpBridge::onRustEvent, this);
    std::call_once(reportingHandlerInstalled, []() {
        previousMessageHandler = qInstallMessageHandler(reportQtMessage);
    });

    if (auto *clip = QGuiApplication::clipboard()) {
        connect(clip, &QClipboard::dataChanged, this, [this, clip]() {
            if (m_updatingClipboardFromRemote) {
                return;
            }
            const QString text = clip->text();
            if (!text.isEmpty()) {
                QJsonObject obj;
                obj.insert(QStringLiteral("action"), QStringLiteral("set_local_clipboard"));
                obj.insert(QStringLiteral("text"), text);
                dispatchJson(QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact)));
            }
        });
    }
}

RdpBridge::~RdpBridge() {
    if (m_audioOutput) {
        m_audioOutput->stop();
        m_audioOutput.reset();
    }
    if (m_handle) {
        rdp_app_destroy(m_handle);
        m_handle = nullptr;
    }
}

void RdpBridge::dispatchJson(const QString &actionJson) {
    if (!m_handle) {
        return;
    }
    const QByteArray utf8 = actionJson.toUtf8();
    rdp_app_dispatch(m_handle, utf8.constData());
}

void RdpBridge::onRustEvent(
    const char *jsonPtr,
    const unsigned char *binPtr,
    std::size_t binLen,
    void *userData
) {
    auto *self = static_cast<RdpBridge *>(userData);
    if (!self || !jsonPtr) {
        return;
    }
    const QString jsonStr = QString::fromUtf8(jsonPtr);
    const QByteArray pcmBytes = (binPtr && binLen > 0)
        ? QByteArray(reinterpret_cast<const char *>(binPtr), static_cast<int>(binLen))
        : QByteArray();

    QMetaObject::invokeMethod(
        self,
        [self, jsonStr, pcmBytes]() {
            self->handleEventOnMainThread(jsonStr, pcmBytes);
        },
        Qt::QueuedConnection
    );
}

void RdpBridge::handleEventOnMainThread(const QString &jsonStr, const QByteArray &pcmBytes) {
    const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
    if (doc.isObject()) {
        const QJsonObject obj = doc.object();
        const QString type = obj.value(QStringLiteral("type")).toString();

        if (type == QStringLiteral("remote_clipboard")) {
            const QString text = obj.value(QStringLiteral("text")).toString();
            if (auto *clip = QGuiApplication::clipboard()) {
                m_updatingClipboardFromRemote = true;
                clip->setText(text);
                m_updatingClipboardFromRemote = false;
            }
            return;
        }

        if (type == QStringLiteral("audio_pcm")) {
            const int rate = obj.value(QStringLiteral("sampleRate")).toInt(44100);
            const int channels = obj.value(QStringLiteral("channels")).toInt(2);
            const int bits = obj.value(QStringLiteral("bitsPerSample")).toInt(16);
            ensureAudioSink(rate, channels, bits);
            if (m_audioDevice && !pcmBytes.isEmpty()) {
                m_audioDevice->write(pcmBytes);
            }
            return;
        }
    }

    emit eventJsonReceived(jsonStr);
}

void RdpBridge::ensureAudioSink(int sampleRate, int channels, int sampleSizeBits) {
    if (m_audioOutput && m_audioRate == sampleRate && m_audioChannels == channels) {
        return;
    }
    if (m_audioOutput) {
        m_audioOutput->stop();
        m_audioOutput.reset();
        m_audioDevice = nullptr;
    }

    QAudioFormat fmt;
    fmt.setSampleRate(sampleRate);
    fmt.setChannelCount(channels);
    fmt.setSampleSize(sampleSizeBits);
    fmt.setCodec(QStringLiteral("audio/pcm"));
    fmt.setByteOrder(QAudioFormat::LittleEndian);
    fmt.setSampleType(QAudioFormat::SignedInt);

    m_audioOutput = std::make_unique<QAudioOutput>(fmt, this);
    m_audioOutput->setBufferSize(32768);
    m_audioDevice = m_audioOutput->start();
    m_audioRate = sampleRate;
    m_audioChannels = channels;
}
