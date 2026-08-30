import QtQuick
import QtQuick.Layouts
import QtQuick 2.15 as Quick
import ClassWidgets.Theme

// 逐字歌词行：按字符拆分，每个字独立播放进入动画（上浮）
// 长文本（超过可用宽度）：开头顶左格静态显示，超出宽度的部分向左滚动展示，
// 最后一个字到达行末（右端）时停止
Item {
    id: line
    property string text: ""
    property int fontSize: 16
    property string anim: "off"       // off=关闭 / float=上浮
    property string lyricColor: "white" // white=白色 / black=黑色 / theme=跟随主题
    property int epoch: 0
    property int availWidth: 300      // 可用宽度（由父级传入，组件宽度固定）
    property int scrollSeconds: 8     // 滚动时长（秒）
    property real scrollDelay: 0.5    // 滚动前停顿（秒）

    width: 300
    height: 22

    // 滚动模式判定：按字符数估算文本宽度（中文全角字符宽=字号）
    property bool longMode: false

    onTextChanged: rebuild()
    onEpochChanged: rebuild()
    onAvailWidthChanged: rebuild()

    // 精确测量文本宽度：逐字测量求和（与 Repeater 逐字渲染一致，不含整串字距调整），
    // 用于超宽判定、滚动距离与停止位置——测量与渲染一致，末字到达右缘即精确停止
    FontMetrics {
        id: fontMetrics
        font.pixelSize: line.fontSize
        font.weight: Font.DemiBold
    }
    function estWidth() {
        var t = line.text
        var w = 0
        for (var i = 0; i < t.length; i++) {
            w += fontMetrics.advanceWidth(t.charAt(i))
        }
        return w
    }

    // 实际行宽：优先用 Row 布局宽度（若已更新），否则用 FontMetrics 逐字测量。
    // 两者在应用字体环境下均与逐字渲染宽度一致，保证"末字到达右缘即停"
    function rowWidth() {
        var w = lineRow.width
        return (w > 1) ? w : line.estWidth()
    }

    function rebuild() {
        longMode = line.availWidth > 0 && estWidth() > line.availWidth
        if (longMode) {
            // 滚动模式：先在起点（头部位于窗口左缘）停顿，再开始滚动
            lineRow.x = 0
            scrollTimer.stop()
            scrollDelayTimer.restart()
        } else {
            // 静态模式：停止滚动，水平居中
            scrollTimer.stop()
            scrollDelayTimer.stop()
            lineRow.x = Math.max(0, (line.availWidth - line.estWidth()) / 2)
        }
    }

    // 滚动前停顿（时长由 scrollDelay 设置控制）
    Timer {
        id: scrollDelayTimer
        interval: Math.max(50, Math.round(line.scrollDelay * 1000))
        repeat: false
        onTriggered: {
            if (!line.longMode) return
            scrollTimer.from = 0
            scrollTimer.to = line.availWidth - line.estWidth()
            scrollTimer.steps = 0
            scrollTimer.totalSteps = Math.max(1, Math.round(line.scrollSeconds * 1000 / 16))
            scrollTimer.start()
        }
    }

    // 帧驱动滚动：匀速向左，最后一个字到达窗口右缘时立即停止
    Timer {
        id: scrollTimer
        interval: 16
        repeat: true
        property real from: 0
        property real to: 0
        property int steps: 0
        property int totalSteps: 240

        onTriggered: {
            steps++
            var t = steps / totalSteps
            // 末字右缘 = 当前位置 + 实际渲染宽；到达窗口右缘即停（不等待总时长跑完）
            if (t >= 1 || lineRow.x + line.rowWidth() <= line.availWidth) {
                lineRow.x = line.availWidth - line.rowWidth()
                stop()
                return
            }
            lineRow.x = from + (to - from) * t
        }
    }

    Row {
        id: lineRow
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            // 绑定直接依赖 text/epoch：文本或重建标记变化时重新求值返回新数组，
            // 触发 Repeater 全量重建并重播逐字动画（var 中间属性赋值不可靠，已弃用）
            model: {
                line.epoch
                return line.text.length > 0 ? line.text.split("") : []
            }

            delegate: Quick.Text {
                id: ch
                text: modelData
                font.pixelSize: line.fontSize
                font.weight: Font.DemiBold
                color: line.lyricColor === "white" ? "#FFFFFF"
                     : line.lyricColor === "black" ? "#000000"
                     : Theme.currentTheme.colors.textColor
                opacity: line.longMode ? 1 : (line.anim === "off" ? 1 : 0)
                y: line.longMode ? 0 : (line.anim === "off" ? 0 : 8)

                // 逐字进入动画仅在静态模式播放；滚动模式整行移动，不逐字
                SequentialAnimation {
                    running: !line.longMode && line.anim !== "off"
                    PauseAnimation {
                        duration: index * (150 / Math.max(1, line.text.length))
                    }
                    ParallelAnimation {
                        NumberAnimation {
                            target: ch; property: "opacity"
                            from: 0
                            to: 1
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                        NumberAnimation {
                            target: ch; property: "y"
                            from: 8
                            to: 0
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
