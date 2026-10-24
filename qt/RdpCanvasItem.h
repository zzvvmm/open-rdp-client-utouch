#pragma once

#include "RdpBridge.h"

#include <QImage>
#include <QPainter>
#include <QQuickPaintedItem>
#include <cstdint>

class RdpCanvasItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QObject *controller READ controller WRITE setController NOTIFY controllerChanged)

public:
    explicit RdpCanvasItem(QQuickItem *parent = nullptr);

    QObject *controller() const { return m_bridge; }
    void setController(QObject *obj);

    Q_INVOKABLE void requestRepaint();

    void paint(QPainter *painter) override;

signals:
    void controllerChanged();

private:
    RdpBridge *m_bridge = nullptr;
    QImage m_frameImage;
    std::uint64_t m_lastSeq = 0;
};
