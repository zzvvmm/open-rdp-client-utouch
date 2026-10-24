#pragma once

#include "rdp_ffi.h"

#include <QAudioOutput>
#include <QByteArray>
#include <QIODevice>
#include <QObject>
#include <QString>
#include <cstdint>
#include <memory>

class RdpBridge final : public QObject {
    Q_OBJECT

public:
    explicit RdpBridge(QObject *parent = nullptr);
    ~RdpBridge() override;

    Q_INVOKABLE void dispatchJson(const QString &actionJson);

    RdpAppHandle *nativeHandle() const { return m_handle; }

signals:
    void eventJsonReceived(const QString &jsonString);

private:
    static void onRustEvent(
        const char *jsonPtr,
        const unsigned char *binPtr,
        std::size_t binLen,
        void *userData
    );

    void handleEventOnMainThread(const QString &jsonStr, const QByteArray &pcmBytes);
    void ensureAudioSink(int sampleRate, int channels, int sampleSizeBits);

    RdpAppHandle *m_handle = nullptr;
    bool m_updatingClipboardFromRemote = false;

    std::unique_ptr<QAudioOutput> m_audioOutput;
    QIODevice *m_audioDevice = nullptr;
    int m_audioRate = 0;
    int m_audioChannels = 0;
};
