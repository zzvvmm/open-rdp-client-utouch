#include "RdpBridge.h"
#include "RdpCanvasItem.h"

#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QUrl>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("rdp-client-ut.zzvvmm"));
    app.setApplicationDisplayName(QStringLiteral("Open RDP Client"));
    app.setOrganizationName(QStringLiteral("rdp-client-ut.zzvvmm"));
    if (!qEnvironmentVariableIsEmpty("DESKTOP_FILE_HINT")) {
        app.setDesktopFileName(qEnvironmentVariable("DESKTOP_FILE_HINT"));
    }

    qmlRegisterType<RdpCanvasItem>("RdpClient", 1, 0, "RdpCanvas");

    RdpBridge bridge;

    QQuickView view;
    view.setTitle(app.applicationDisplayName());
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    view.rootContext()->setContextProperty(QStringLiteral("RdpBridge"), &bridge);
    view.setSource(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    if (view.status() == QQuickView::Error) {
        if (!view.errors().isEmpty()) {
            const auto error = view.errors().first();
            const auto file = error.url().toString().toUtf8();
            rdp_report_ui_error("qml_load", file.constData(), error.line() > 0 ? error.line() : 0, 1);
        }
        return 1;
    }

    view.resize(450, 820);
    view.show();

    return app.exec();
}
