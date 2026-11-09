#pragma once

#include "RdpBridge.h"
#include <QGuiApplication>
#include <QFont>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>
#include <memory>

// Set the application font before QML creates its application singleton.
inline void configureSmokeFont(QGuiApplication &app) {
    if (!app.arguments().contains(QStringLiteral("--smoke-test"))) return;
    bool validScale = false;
    const double fontScale = qEnvironmentVariable("OPEN_RDP_SMOKE_FONT_SCALE").toDouble(&validScale);
    if (validScale && fontScale >= 0.5 && fontScale <= 3.0) {
        QFont font = app.font();
        if (font.pointSizeF() > 0) font.setPointSizeF(font.pointSizeF() * fontScale);
        else if (font.pixelSize() > 0) font.setPixelSize(qRound(font.pixelSize() * fontScale));
        app.setFont(font);
    }
}

// Explicit test mode; callers provide isolated storage and only the offline demo
// is connected. The same check exercises installed Qt 5 and Qt 6 resources.
inline void configureSmokeTest(QGuiApplication &app, RdpBridge &bridge, QObject *root, QQuickWindow *window) {
    if (!app.arguments().contains(QStringLiteral("--smoke-test"))) return;
    const double fontScale = qEnvironmentVariable("OPEN_RDP_SMOKE_FONT_SCALE").toDouble();
    if (fontScale >= 0.5 && fontScale <= 3.0 && root->metaObject()->indexOfMethod("applySmokeFontScale(QVariant)") >= 0)
        QMetaObject::invokeMethod(root, "applySmokeFontScale", Q_ARG(QVariant, QVariant(fontScale)));
    const int width = qEnvironmentVariableIntValue("OPEN_RDP_SMOKE_WIDTH");
    const int height = qEnvironmentVariableIntValue("OPEN_RDP_SMOKE_HEIGHT");
    if (width > 0 && height > 0) window->resize(width, height);
    auto connected = std::make_shared<bool>(false);
    QObject::connect(&bridge, &RdpBridge::eventJsonReceived, &app, [root, connected](const QString &json) {
        const auto event = QJsonDocument::fromJson(json.toUtf8()).object();
        if (event.value("type").toString() == "session_stage" && event.value("stage").toString() == "connected") *connected = true;
        if (event.value("type").toString() == "certificate_prompt" && event.value("host").toString() == "demo.local")
            QMetaObject::invokeMethod(root, "acceptDemoCertificate", Qt::QueuedConnection);
    });
    const QString snapshot = qEnvironmentVariable("OPEN_RDP_SMOKE_SNAPSHOT");
    QTimer::singleShot(300, &app, [root, window, snapshot]() {
        if (!snapshot.isEmpty()) window->grabWindow().save(snapshot + "-dashboard.png");
        QMetaObject::invokeMethod(root, "startDemo");
    });
    QTimer::singleShot(4000, &app, [&app, &bridge, window, snapshot, connected]() {
        std::uint16_t width = 0, height = 0;
        std::uint64_t sequence = 0;
        const bool live = rdp_app_framebuffer_size(bridge.nativeHandle(), &width, &height, &sequence) == 0 && width > 0 && height > 0 && sequence > 0;
        const QImage frame = window->grabWindow();
        if (!snapshot.isEmpty()) frame.save(snapshot + "-session.png");
        app.exit(*connected && live && !frame.isNull() ? 0 : 2);
    });
}
