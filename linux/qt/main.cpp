#include "DesktopInput.h"
#include "RdpBridge.h"
#include "RdpCanvasItem.h"
#include "SmokeTest.h"

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
    configureSmokeFont(app);
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
    configureSmokeTest(app, bridge, engine.rootObjects().first(), qobject_cast<QQuickWindow *>(engine.rootObjects().first()));
    return app.exec();
}
