#include "DesktopInput.h"
#include "RdpBridge.h"
#include "RdpCanvasItem.h"

#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <memory>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("open-rdp-client"));
    app.setApplicationDisplayName(QStringLiteral("Open RDP Client"));
    app.setOrganizationName(QStringLiteral("open-rdp-client"));
    app.setDesktopFileName(QStringLiteral("open-rdp-client"));
    QQuickStyle::setStyle(QStringLiteral("Fusion"));
    qmlRegisterType<RdpCanvasItem>("RdpClient", 1, 0, "RdpCanvas");
    qmlRegisterType<DesktopInput>("RdpClient", 1, 0, "DesktopInput");
    RdpBridge bridge;
    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/"));
    engine.rootContext()->setContextProperty(QStringLiteral("RdpBridge"), &bridge);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        rdp_report_ui_error("qml_load", "qml/Main.qml", 0, 1);
        return 1;
    }
    // Deterministic installed-package verification, with caller-provided isolated
    // XDG directories. Connects only to the built-in offline demo.
    if (app.arguments().contains(QStringLiteral("--smoke-test"))) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        auto connected = std::make_shared<bool>(false);
        QObject::connect(&bridge, &RdpBridge::eventJsonReceived, &app, [&engine, connected](const QString &json) {
            const auto event = QJsonDocument::fromJson(json.toUtf8()).object();
            if (event.value("type").toString() == "session_stage" && event.value("stage").toString() == "connected")
                *connected = true;
            if (event.value("type").toString() == "certificate_prompt" && event.value("host").toString() == "demo.local") {
                auto *dialog = engine.rootObjects().first()->findChild<QObject *>(QStringLiteral("certificateDialog"));
                if (dialog) QMetaObject::invokeMethod(dialog, "decision", Q_ARG(QString, QStringLiteral("trust_once")));
            }
        });
        const QString snapshot = qEnvironmentVariable("OPEN_RDP_SMOKE_SNAPSHOT");
        QTimer::singleShot(100, &app, [&engine, window, snapshot]() {
            if (!snapshot.isEmpty()) window->grabWindow().save(snapshot + "-dashboard.png");
            QMetaObject::invokeMethod(engine.rootObjects().first(), "startDemo");
        });
        QTimer::singleShot(3500, &app, [window, &bridge, &app, snapshot, connected]() {
            std::uint16_t width = 0, height = 0;
            std::uint64_t sequence = 0;
            const bool live = rdp_app_framebuffer_size(bridge.nativeHandle(), &width, &height, &sequence) == 0
                && width > 0 && height > 0 && sequence > 0;
            const QImage frame = window->grabWindow();
            if (!snapshot.isEmpty()) frame.save(snapshot + "-session.png");
            app.exit(*connected && live && !frame.isNull() ? 0 : 2);
        });
    }
    return app.exec();
}
