import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick 2.15 as Quick
import RinUI
import ClassWidgets.Theme

Widget {
    id: root
    text: qsTr("歌词")

    // 固定组件宽度，与其他组件保持一致（不随设置改变）
    implicitWidth: 300

    // ---- 设置 ----
    property int lyricSize: root.settings && root.settings.lyric_font_size !== undefined
                            ? root.settings.lyric_font_size : 16
    property int extraSize: root.settings && root.settings.extra_font_size !== undefined
                            ? root.settings.extra_font_size : 12
    property string animMode: root.settings && root.settings.anim_mode === "float"
                              ? "float" : "off"
    property int scrollSeconds: root.settings && root.settings.scroll_seconds !== undefined
                                ? root.settings.scroll_seconds : 8
    property real scrollDelay: root.settings && root.settings.scroll_delay !== undefined
                               ? root.settings.scroll_delay : 0.5
    property bool autoShow: root.settings && root.settings.auto_show !== undefined
                            ? root.settings.auto_show : true
    property string lyricColor: root.settings && root.settings.lyric_color !== undefined
                                ? root.settings.lyric_color : "white"

    // ---- 灵动显隐：有歌词自动弹出，无歌词自动隐藏（编辑模式下始终显示）----
    property bool autoHidden: false
    readonly property bool shouldShow: editMode
        || (backend.lyricStatus === "ok" && root.autoShow && !autoHidden)
    property bool actualVisible: true

    function updateVisibility() {
        if (shouldShow) {
            if (!actualVisible) {
                actualVisible = true
                exitAnim.stop()
                enterAnim.start()
            }
        } else {
            enterAnim.stop()
            exitAnim.start()
        }
    }
    onShouldShowChanged: updateVisibility()

    Component.onCompleted: {
        actualVisible = shouldShow
        idleTimer.start()
    }

    width: actualVisible ? implicitWidth : 0
    visible: actualVisible

    // 入场动画（类似灵动通知：弹性放大 + 淡入）
    SequentialAnimation {
        id: enterAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "scale"; from: 0.8; to: 1; duration: 400; easing.type: Easing.OutBack }
        }
        onFinished: actualVisible = shouldShow
    }

    // 退场动画（缩小 + 淡出，完成后隐藏）
    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; from: 1; to: 0; duration: 200; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "scale"; from: 1; to: 0.9; duration: 250; easing.type: Easing.InQuad }
        }
        onFinished: actualVisible = shouldShow
    }

    // 空闲隐藏：30 秒没有新歌词则自动隐藏（如音乐软件停止推送）
    Timer {
        id: idleTimer
        interval: 30000
        repeat: false
        onTriggered: {
            if (backend.lyricStatus === "ok") autoHidden = true
        }
    }

    // ---- 切换控制：新歌词到达时上一段立即消失，下一段进入（逐字/滚动）----
    property string shownLyric: backend.lyricText
    property string prevShown: ""

    onShownLyricChanged: {
        if (shownLyric === prevShown) return
        // 新歌词：重建行内容并重新播放进入动画
        newLine.text = shownLyric
        newLine.epoch++
        prevShown = shownLyric
        idleTimer.restart()
        autoHidden = false
    }

    // 等待状态提示（编辑模式下可见）
    Quick.Text {
        id: statusText
        anchors.centerIn: parent
        width: parent.width - 24
        visible: backend.lyricStatus !== "ok"
        text: qsTr("等待音乐软件侧传输歌词...")
        horizontalAlignment: Quick.Text.AlignHCenter
        wrapMode: Quick.Text.Wrap
        color: Theme.currentTheme.colors.textSecondaryColor
        font.pixelSize: 13
    }

    // 歌词层：固定尺寸容器（不随内容变化，避免撑大组件）
    // 组件总高由应用固定（normal 100 / mini 56），内容区约 38/34px
    Item {
        id: fixedArea
        width: 300
        height: root.miniMode ? 34 : 38
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        Item {
            id: lyricArea
            anchors.fill: parent
            visible: backend.lyricStatus === "ok"

            // 主歌词滚动窗口：左右各留 24px 边距，歌词在窗口内滚动，
            // 裁剪只发生在窗口边缘，滚动全程与组件边界保持距离
            Item {
                id: lyricScrollView
                x: 24
                width: 252
                height: 21
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -8
                clip: true

                LyricsLine {
                    id: newLine
                    objectName: "lyricNewLine"
                    anchors.fill: parent
                    fontSize: root.lyricSize
                    anim: root.animMode
                    lyricColor: root.lyricColor
                    text: root.shownLyric
                    availWidth: 252
                    scrollSeconds: root.scrollSeconds
                    scrollDelay: root.scrollDelay
                }
            }

            // 译文窗口：同样左右各留 24px 边距
            Item {
                id: extraSlot
                anchors.top: lyricScrollView.bottom
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: 252
                height: 16
                clip: true

                Quick.Text {
                    id: extraLabel
                    width: 252
                    x: Math.max(0, (252 - contentWidth) / 2)
                    visible: backend.extraText !== ""
                    text: backend.extraText
                    color: Theme.currentTheme.colors.textSecondaryColor
                    font.pixelSize: root.extraSize
                    opacity: 0

                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

                    // 滚动前停顿（时长可由设置调整，默认 0.5s）
                    Timer {
                        id: extraScrollDelay
                        interval: Math.max(50, Math.round(root.scrollDelay * 1000))
                        repeat: false
                        onTriggered: {
                            if (extraLabel.contentWidth <= extraLabel.width) return
                            extraScrollTimer.from = 0
                            extraScrollTimer.to = extraLabel.width - extraLabel.contentWidth
                            extraScrollTimer.steps = 0
                            extraScrollTimer.totalSteps = Math.max(1, Math.round(root.scrollSeconds * 1000 / 16))
                            extraScrollTimer.start()
                        }
                    }

                    // 译文滚动：与主歌词一致，在窗口内滚动（窗口与边界保持 24px 距离）
                    Timer {
                        id: extraScrollTimer
                        interval: 16
                        repeat: true
                        property real from: 0
                        property real to: 0
                        property int steps: 0
                        property int totalSteps: 240

                        onTriggered: {
                            steps++
                            var t = steps / totalSteps
                            if (t >= 1) {
                                // 终点：最后一个字停在窗口右缘（用实际渲染宽）
                                extraLabel.x = extraLabel.width - extraLabel.contentWidth
                                stop()
                                return
                            }
                            extraLabel.x = from + (to - from) * t
                        }
                    }

                    // 用 contentWidth（实际渲染宽）判断是否溢出，避免布局时序误判
                    function place() {
                        if (contentWidth > width) {
                            x = 0
                            extraScrollTimer.stop()
                            extraScrollDelay.restart()
                        } else {
                            extraScrollTimer.stop()
                            extraScrollDelay.stop()
                            x = Math.max(0, (252 - contentWidth) / 2)
                        }
                    }

                    onTextChanged: {
                        if (text !== "") {
                            opacity = 0
                            opacity = 1
                            place()
                        }
                    }
                    // 文本布局完成后校正水平位置（contentWidth 初始为 0，就绪后再定位）
                    onContentWidthChanged: {
                        if (text !== "") place()
                    }
                }
            }
        }
    }
}
