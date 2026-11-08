#include "DesktopInput.h"
#include "RdpCanvasItem.h"
#include <QJsonDocument>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickStyle>
#include <QtQuickTest/quicktest.h>

class FixtureBridge : public QObject {
    Q_OBJECT
public:
    Q_INVOKABLE void dispatchJson(const QString &json) {
        emit actionDispatched(QJsonDocument::fromJson(json.toUtf8()).toVariant().toMap());
    }
    Q_INVOKABLE void deliverEvent(const QVariantMap &event) {
        emit eventJsonReceived(QString::fromUtf8(QJsonDocument::fromVariant(event).toJson(QJsonDocument::Compact)));
    }
signals:
    void eventJsonReceived(const QString &jsonString);
    void actionDispatched(const QVariantMap &action);
};
class Setup : public QObject {
    Q_OBJECT
    FixtureBridge bridge;
public slots:
    void applicationAvailable() {
        QQuickStyle::setStyle("Fusion");
        qmlRegisterType<RdpCanvasItem>("RdpClient", 1, 0, "RdpCanvas");
        qmlRegisterType<DesktopInput>("RdpClient", 1, 0, "DesktopInput");
    }
    void qmlEngineAvailable(QQmlEngine *engine) {
        engine->rootContext()->setContextProperty("RdpBridge", &bridge);
    }
};
QUICK_TEST_MAIN_WITH_SETUP(desktop, Setup)
#include "qml_main.moc"
