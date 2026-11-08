#include "DesktopInput.h"

#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>

DesktopInput::DesktopInput(QQuickItem *parent) : QQuickItem(parent) {
    setFlag(ItemAcceptsInputMethod, true);
    setActiveFocusOnTab(false);
    connect(this, &QQuickItem::enabledChanged, this, [this]() {
        if (!isEnabled()) releaseAll();
    });
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state != Qt::ApplicationActive) releaseAll();
    });
}

void DesktopInput::sendKey(int key, const QString &text, bool pressed) {
    emit actionRequested({{"action", "send_qt_key"}, {"qtKey", key}, {"text", text}, {"pressed", pressed}});
}

bool DesktopInput::event(QEvent *event) {
    if (event->type() == QEvent::ShortcutOverride && isEnabled() && hasActiveFocus()) {
        event->accept();
        return true;
    }
    return QQuickItem::event(event);
}

void DesktopInput::keyPressEvent(QKeyEvent *event) {
    const auto modifiers = event->modifiers() & (Qt::ControlModifier | Qt::AltModifier | Qt::ShiftModifier | Qt::MetaModifier);
    if ((event->key() == Qt::Key_Return || event->key() == Qt::Key_Enter)
            && modifiers == (Qt::ControlModifier | Qt::AltModifier)) {
        releaseAll();
        if (!event->isAutoRepeat()) emit fullscreenRequested();
    } else {
        m_pressed.insert(event->key());
        sendKey(event->key(), event->text(), true);
    }
    event->accept();
}

void DesktopInput::keyReleaseEvent(QKeyEvent *event) {
    if (!event->isAutoRepeat() && m_pressed.remove(event->key()))
        sendKey(event->key(), QString(), false);
    event->accept();
}

void DesktopInput::releaseAll() {
    const auto pressed = m_pressed;
    m_pressed.clear();
    for (int key : pressed) sendKey(key, QString(), false);
}

void DesktopInput::focusOutEvent(QFocusEvent *event) {
    releaseAll();
    QQuickItem::focusOutEvent(event);
}

void DesktopInput::inputMethodEvent(QInputMethodEvent *event) {
    if (!event->commitString().isEmpty()) sendKey(0, event->commitString(), true);
    event->accept();
}
