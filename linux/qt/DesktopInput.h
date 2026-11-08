#pragma once

#include <QQuickItem>
#include <QSet>
#include <QVariantMap>

// Native keyboard events retain key-up semantics (including held modifiers).
class DesktopInput : public QQuickItem {
    Q_OBJECT
public:
    explicit DesktopInput(QQuickItem *parent = nullptr);
    Q_INVOKABLE void releaseAll();

signals:
    void actionRequested(const QVariantMap &action);
    void fullscreenRequested();

protected:
    bool event(QEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void keyReleaseEvent(QKeyEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void inputMethodEvent(QInputMethodEvent *event) override;

private:
    void sendKey(int key, const QString &text, bool pressed);
    QSet<int> m_pressed;
};
