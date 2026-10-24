#include "RdpCanvasItem.h"

#include <QRectF>

RdpCanvasItem::RdpCanvasItem(QQuickItem *parent)
    : QQuickPaintedItem(parent) {
    setRenderTarget(QQuickPaintedItem::FramebufferObject);
    setPerformanceHint(QQuickPaintedItem::FastFBOResizing, true);
}

void RdpCanvasItem::setController(QObject *obj) {
    auto *bridge = qobject_cast<RdpBridge *>(obj);
    if (m_bridge == bridge) {
        return;
    }
    m_bridge = bridge;
    m_lastSeq = 0;
    emit controllerChanged();
    update();
}

void RdpCanvasItem::requestRepaint() {
    update();
}

void RdpCanvasItem::paint(QPainter *painter) {
    if (!painter) {
        return;
    }
    painter->setRenderHint(QPainter::SmoothPixmapTransform, true);

    if (!m_bridge || !m_bridge->nativeHandle()) {
        painter->fillRect(boundingRect(), QColor(14, 19, 27));
        return;
    }

    std::uint16_t fbWidth = 0;
    std::uint16_t fbHeight = 0;
    std::uint64_t fbSeq = 0;

    if (rdp_app_framebuffer_size(m_bridge->nativeHandle(), &fbWidth, &fbHeight, &fbSeq) == 0
        && fbWidth > 0 && fbHeight > 0) {
        if (m_frameImage.width() != fbWidth
            || m_frameImage.height() != fbHeight
            || m_frameImage.format() != QImage::Format_RGBA8888) {
            m_frameImage = QImage(fbWidth, fbHeight, QImage::Format_RGBA8888);
            m_lastSeq = 0;
        }

        if (fbSeq != m_lastSeq || m_lastSeq == 0) {
            const std::size_t byteCount = static_cast<std::size_t>(m_frameImage.sizeInBytes());
            if (rdp_app_copy_framebuffer_rgba(m_bridge->nativeHandle(), m_frameImage.bits(), byteCount) == 0) {
                m_lastSeq = fbSeq;
            }
        }
    }

    if (!m_frameImage.isNull()) {
        painter->drawImage(boundingRect(), m_frameImage);
    } else {
        painter->fillRect(boundingRect(), QColor(14, 19, 27));
    }
}
