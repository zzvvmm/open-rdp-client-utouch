#include "DesktopInput.h"
#include <QQuickWindow>
#include <QSignalSpy>
#include <QtTest>

class InputTest : public QObject {
    Q_OBJECT
private slots:
    void held_keys_release_on_focus_loss() {
        QQuickWindow window;
        DesktopInput input(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        input.forceActiveFocus();
        QSignalSpy actions(&input, &DesktopInput::actionRequested);
        QTest::keyPress(&window, Qt::Key_Control);
        QTest::keyPress(&window, Qt::Key_A);
        QVERIFY(actions.count() >= 2);
        const int presses = actions.count();
        QQuickItem other(window.contentItem());
        other.forceActiveFocus();
        QVERIFY(!input.hasActiveFocus());
        QTRY_COMPARE(actions.count(), presses + 2);
        for (int i = presses; i < actions.count(); ++i)
            QCOMPARE(actions.at(i).at(0).toMap().value("pressed").toBool(), false);
        input.releaseAll();
        QCOMPARE(actions.count(), presses + 2);
    }
    void escape_and_tab_are_forwarded_with_releases() {
        QQuickWindow window;
        DesktopInput input(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        input.forceActiveFocus();
        QSignalSpy actions(&input, &DesktopInput::actionRequested);
        QTest::keyClick(&window, Qt::Key_Escape);
        QTest::keyClick(&window, Qt::Key_Tab);
        QCOMPARE(actions.count(), 4);
        QCOMPARE(actions.at(0).at(0).toMap().value("qtKey").toInt(), int(Qt::Key_Escape));
        QCOMPARE(actions.at(1).at(0).toMap().value("pressed").toBool(), false);
        QCOMPARE(actions.at(3).at(0).toMap().value("qtKey").toInt(), int(Qt::Key_Tab));
    }
    void fullscreen_chord_is_local_and_disabling_releases_input() {
        QQuickWindow window;
        DesktopInput input(window.contentItem());
        window.show();
        QVERIFY(QTest::qWaitForWindowExposed(&window));
        input.forceActiveFocus();
        QSignalSpy fullscreen(&input, &DesktopInput::fullscreenRequested);
        QSignalSpy actions(&input, &DesktopInput::actionRequested);
        QTest::keyClick(&window, Qt::Key_Return, Qt::ControlModifier | Qt::AltModifier);
        QCOMPARE(fullscreen.count(), 1);
        for (const auto &entry : actions)
            QVERIFY(entry.at(0).toMap().value("qtKey").toInt() != Qt::Key_Return);
        actions.clear();
        QTest::keyPress(&window, Qt::Key_Shift);
        input.setEnabled(false);
        QCOMPARE(actions.count(), 2);
        QCOMPARE(actions.last().at(0).toMap().value("pressed").toBool(), false);
    }
};
QTEST_MAIN(InputTest)
#include "tst_DesktopInput.moc"
