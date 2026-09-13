import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import QtQuick 2.15 as Quick
import RinUI
import ClassWidgets.Theme

// 歌词岛：上一句 / 当前句 / 附加行（译文或下一句）+ 底部播放进度条。
// - 当前句参考 BetterNCM 的 LyricBar：逐字/逐词点亮，唱到的字不透明并上浮 2px。
// - 附加行区分两类：译文用与当前歌词相同的字号与亮度；下一句做虚化（真模糊）。
// - 背景：SMTC 专辑封面 → 模糊 → 圆角遮罩，歌词颜色按方案自适应。
Widget {
    id: root
    text: ""

    implicitWidth: 300

    // ---- 设置 ----
    property int mainSize: root.settings && root.settings.lyric_font_size !== undefined
                           ? root.settings.lyric_font_size : 13
    property int subSize: root.settings && root.settings.sub_font_size !== undefined
                          ? root.settings.sub_font_size : 10
    property bool autoShow: root.settings && root.settings.auto_show !== undefined
                            ? root.settings.auto_show : true
    property bool showProgress: root.settings && root.settings.show_progress !== undefined
                                ? root.settings.show_progress : true
    property bool allowUnverified: root.settings && root.settings.progress_unverified !== undefined
                                   ? root.settings.progress_unverified : true
    property bool showCover: root.settings && root.settings.show_cover !== undefined
                             ? root.settings.show_cover : true
    // auto / light / dark / vivid / soft / tinted / theme / white / black / custom
    property string colorMode: root.settings && root.settings.lyric_color !== undefined
                               ? root.settings.lyric_color : "auto"
    property string customColor: root.settings && root.settings.lyric_color_custom !== undefined
                                 ? root.settings.lyric_color_custom : "#ffffff"

    // ---- SMTC 体检 ----
    // 只有确认 SMTC 与歌词渠道是同一首歌，才启用需要 SMTC 的功能（进度条 / 封面背景 / 逐字同步）。
    // 明确"不是同一首歌"时一律停用；状态未知时由"未核验也使用"开关决定。
    readonly property bool smtcVerified: backend.matchState === "matched"
    readonly property bool smtcUsable: root.smtcVerified
                                       || (root.allowUnverified && backend.matchState === "unknown")
    onSmtcUsableChanged: backend.smtcGate = root.smtcUsable

    // ---- 封面与配色 ----
    readonly property string coverUrl: backend.coverUrl
    readonly property bool hasCover: root.showCover && root.smtcUsable && root.coverUrl !== ""
    readonly property string coverColor: backend.coverColor !== "" ? backend.coverColor : "#808080"
    // 没有封面时退回主题明暗
    readonly property bool coverLight: root.hasCover ? backend.coverIsLight : !Theme.isDark()

    readonly property real cvH: root.coverColor.hslHue
    readonly property real cvS: root.coverColor.hslSaturation
    readonly property real cvL: root.coverColor.hslLightness

    // 歌词前景色
    readonly property color fgColor: {
        switch (root.colorMode) {
        case "auto":   return root.coverLight ? "#15171c" : "#FFFFFF"
        case "light":  return "#FFFFFF"
        case "dark":   return "#15171c"
        case "vivid":  return Qt.hsla(root.cvH, 0.95, root.coverLight ? 0.30 : 0.70, 1.0)
        case "soft":   return Qt.hsla(root.cvH, 0.34, root.coverLight ? 0.24 : 0.86, 1.0)
        case "tinted": return Qt.hsla(root.cvH, 0.55, root.coverLight ? 0.18 : 0.90, 1.0)
        case "white":  return "#FFFFFF"
        case "black":  return "#000000"
        case "custom": return root.customColor
        default:       return Theme.currentTheme.colors.textColor
        }
    }

    // 压在封面上的遮罩（保证歌词可读）
    readonly property color scrimColor: {
        switch (root.colorMode) {
        case "dark":  return "#FFFFFF"
        case "light": return "#000000"
        case "vivid": return "#000000"
        case "tinted":
            return Qt.hsla(root.cvH, root.coverLight ? 0.20 : 0.45,
                           root.coverLight ? 0.92 : 0.08, 1.0)
        default: return root.coverLight ? "#FFFFFF" : "#000000"
        }
    }
    readonly property real scrimOpacity: {
        switch (root.colorMode) {
        case "vivid":  return 0.50
        case "soft":   return 0.62
        case "tinted": return 0.68
        case "dark":   return 0.72
        case "light":  return 0.55
        default:       return 0.58
        }
    }

    // karaoke 参数（对齐 LyricBar）
    readonly property real unlitOpacity: 0.34
    readonly property real idleOpacity: 0.42
    readonly property real nextOpacity: 0.55
    readonly property real liftY: -2
    readonly property int karaokeFade: 200
    readonly property real nextBlur: 0.75
    readonly property real coverBlurRadius: 32

    // 自适应：按上一句的实际长度定速，并提前约 1 秒播放完
    readonly property int karaokeDuration: backend.lineDuration > 0
                                           ? Math.max(1200, backend.lineDuration - 1000)
                                           : 4000

    // 逐字高亮：默认开；关掉则当前行整行满亮度
    property bool karaokeOn: root.settings && root.settings.karaoke_enabled !== undefined
                             ? root.settings.karaoke_enabled : true

    property bool hasLyrics: backend.hasLyrics

    // 分词：CJK 每字一个 token，西文按词，空白单独保留
    function tokenize(s) {
        if (!s)
            return []
        var re = /[\u4e00-\u9fff\u3400-\u4dbf\u3040-\u30ff\uac00-\ud7af]|[^\s\u4e00-\u9fff\u3400-\u4dbf\u3040-\u30ff\uac00-\ud7af]+|\s+/g
        return s.match(re) || []
    }

    // ---- 背景：模糊封面 ----
    backgroundArea: Item {
        anchors.fill: parent
        visible: root.hasCover

        Image {
            id: coverSrc
            anchors.fill: parent
            source: root.coverUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: false
            smooth: true
        }

        FastBlur {
            id: coverBlur
            anchors.fill: parent
            source: coverSrc
            radius: root.coverBlurRadius
            visible: false
        }

        // 圆角遮罩源
        Item {
            id: coverMask
            anchors.fill: parent
            visible: false
            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: "white"
            }
        }

        OpacityMask {
            anchors.fill: parent
            source: coverBlur
            maskSource: coverMask
        }

        // 可读性遮罩
        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: root.scrimColor
            opacity: root.scrimOpacity
        }
    }

    // 灵动显隐
    property bool autoHidden: false
    readonly property bool shouldShow: editMode
        || ((root.hasLyrics || backend.lyricStatus === "ok") && root.autoShow && !autoHidden)
    property bool actualVisible: true

    // 歌曲暂停 / 停止多久后自动隐藏
    readonly property int pauseHideMs: 10000
    // 拿不到播放状态时的兜底：多久没有新歌词就隐藏
    readonly property int quietHideMs: 60000
    // 已知在暂停 / 已停止（不看核验闸门：隐藏与否跟"是不是同一首歌"无关）
    readonly property bool playbackStalled: backend.playbackKnown && backend.playbackPaused

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
        backend.smtcGate = root.smtcUsable
        actualVisible = shouldShow
        quietTimer.start()
    }

    width: actualVisible ? implicitWidth : 0
    visible: actualVisible

    SequentialAnimation {
        id: enterAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "scale"; from: 0.94; to: 1; duration: 360; easing.type: Easing.OutCubic }
        }
        onFinished: actualVisible = shouldShow
    }
    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; from: 1; to: 0; duration: 220; easing.type: Easing.InQuad }
            NumberAnimation { target: root; property: "scale"; from: 1; to: 0.97; duration: 240; easing.type: Easing.InQuad }
        }
        onFinished: actualVisible = shouldShow
    }

    // 暂停 / 停止计时：连续停住超过阈值就自动隐藏
    Timer {
        id: pauseTimer
        interval: root.pauseHideMs
        repeat: false
        onTriggered: {
            if (root.hasLyrics) root.autoHidden = true
        }
    }

    // 兜底：拿不到播放状态时，长时间没有新歌词就隐藏
    Timer {
        id: quietTimer
        interval: root.quietHideMs
        repeat: false
        onTriggered: {
            if (root.hasLyrics && !backend.playbackKnown) root.autoHidden = true
        }
    }

    Connections {
        target: backend
        function onProgressTick() {
            if (root.playbackStalled) {
                if (!pauseTimer.running) pauseTimer.start()
            } else if (backend.playbackKnown) {
                // 明确在播放 → 取消隐藏
                pauseTimer.stop()
                root.autoHidden = false
            }
            // 拿不到播放状态时不动 autoHidden，交给 quietTimer
        }
        function onLinesDirty() {
            quietTimer.restart()
            pauseTimer.stop()
            root.autoHidden = false
        }
    }

    // ---- 主体 ----
    Item {
        id: content
        anchors.fill: parent
        anchors.bottomMargin: root.miniMode ? -4 : -12
        visible: root.hasLyrics

        readonly property int visibleRows: root.miniMode ? 1 : 3
        readonly property real rowH: Math.max(12, lyricView.height / visibleRows)

        Quick.ListView {
            id: lyricView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: progressBar.top
            anchors.bottomMargin: 4
            clip: true
            model: backend.lyricModel
            currentIndex: backend.currentIndex

            highlightRangeMode: Quick.ListView.StrictlyEnforceRange
            preferredHighlightBegin: (height - content.rowH) / 2
            preferredHighlightEnd: (height - content.rowH) / 2 + content.rowH
            highlightMoveDuration: 950
            snapMode: Quick.ListView.SnapToItem
            boundsBehavior: Quick.Flickable.StopAtBounds
            interactive: false

            delegate: Item {
                id: cell
                width: lyricView.width
                height: content.rowH
                clip: true

                // 行类型（来自模型）
                readonly property string kind: (rowKind !== undefined) ? rowKind : "line"
                readonly property string ekind: (extraKind !== undefined) ? extraKind : ""
                readonly property bool isCur: Quick.ListView.isCurrentItem && cell.kind === "line"
                readonly property bool isTrans: cell.kind === "extra" && cell.ekind === "trans"
                readonly property bool isNext: cell.kind === "extra" && cell.ekind === "next"
                // 译文与当前歌词同字号；其余用副字号
                readonly property int fs: (cell.isCur || cell.isTrans) ? root.mainSize : root.subSize
                readonly property var tokens: root.tokenize((lineText !== undefined) ? lineText : "")
                readonly property int tokenCount: tokens.length
                readonly property real textW: tokenRow.width
                readonly property bool overflow: textW >= cell.width - 1
                // 横向滚动：当前句必须在本句时长内滚完（留 700ms 起滚缓冲）
                readonly property int marqueeMs: cell.isCur
                                                 ? Math.max(900, root.karaokeDuration - 700)
                                                 : Math.max(3200, (cell.textW - cell.width) * 38)
                property real litCount: 0

                Item {
                    id: lineRoot
                    y: 0
                    height: cell.height
                    width: Math.max(cell.textW, 1)
                    scale: cell.isCur ? 1.0 : 0.9

                    Behavior on scale {
                        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
                    }

                    Row {
                        id: tokenRow
                        y: 0
                        height: cell.height
                        spacing: 0

                        Repeater {
                            id: tokenRepeater
                            model: cell.tokens
                            delegate: Quick.Text {
                                text: modelData
                                height: cell.height
                                verticalAlignment: Quick.Text.AlignVCenter
                                font.pixelSize: cell.fs
                                font.weight: Font.DemiBold
                                color: root.fgColor
                                opacity: cell.isCur
                                         ? ((!root.karaokeOn || index < cell.litCount) ? 1.0 : root.unlitOpacity)
                                         : cell.isTrans ? 1.0
                                         : cell.isNext ? root.nextOpacity
                                         : root.idleOpacity
                                y: (cell.isCur && root.karaokeOn && index < cell.litCount) ? root.liftY : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: root.karaokeFade; easing.type: Easing.OutQuad }
                                }
                                Behavior on y {
                                    NumberAnimation { duration: root.karaokeFade; easing.type: Easing.OutQuad }
                                }
                            }
                        }

                        // 下一句：虚化（整行模糊）
                        layer.enabled: cell.isNext
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: root.nextBlur
                            blurMax: 24
                            autoPaddingEnabled: true
                        }
                    }
                }

                NumberAnimation {
                    id: karaoke
                    target: cell
                    property: "litCount"
                    from: 0
                    to: cell.tokenCount
                    duration: root.karaokeDuration
                    easing.type: Easing.Linear
                }

                function startKaraoke() {
                    karaoke.stop()
                    karaoke.paused = false
                    cell.litCount = 0
                    if (cell.isCur && cell.tokenCount > 0 && root.karaokeOn)
                        cell.syncKaraoke()
                }

                // 混合驱动：优先用 SMTC 的真实播放位置对齐；
                // 后端约每 500ms 刷新一次进度，每次都重新校准，
                // 于是"读到的字"与播放同步进退，暂停时定格。
                function syncKaraoke() {
                    if (!(cell.isCur && root.karaokeOn && cell.tokenCount > 0))
                        return
                    var p = backend.lineProgress
                    if (p < 0) {
                        // 没有可用的 SMTC 进度：退回按上一句节奏估算。
                        // 已读完就不再重播（否则每个心跳都会从头高亮）。
                        if (cell.litCount >= cell.tokenCount - 0.001)
                            return
                        if (!karaoke.running) {
                            karaoke.from = 0
                            karaoke.to = cell.tokenCount
                            karaoke.duration = root.karaokeDuration
                            karaoke.start()
                        }
                        // 估算动画也要跟着播放状态走：暂停即定格，继续播放再接上
                        if (backend.playbackPaused) {
                            if (!karaoke.paused)
                                karaoke.pause()
                        } else if (karaoke.paused) {
                            karaoke.resume()
                        }
                        return
                    }
                    karaoke.stop()
                    cell.litCount = p * cell.tokenCount
                    if (!backend.linePlaying)
                        return                              // 暂停：定格在真实进度
                    karaoke.from = cell.litCount
                    karaoke.to = cell.tokenCount
                    karaoke.duration = Math.max(250, backend.lineRemainMs)
                    karaoke.start()
                }

                // 播放暂停 / 停止时让本行的动画一起停住，恢复播放再接上
                function syncAnim() {
                    if (root.playbackStalled) {
                        if (marquee.running && !marquee.paused)
                            marquee.pause()
                    } else if (marquee.paused) {
                        marquee.resume()
                    }
                    syncKaraoke()
                }

                // 后端每次刷新进度就校准一次
                Connections {
                    target: backend
                    function onProgressTick() {
                        cell.syncAnim()
                    }
                }

                function relayout() {
                    marquee.stop()
                    lineRoot.x = 0
                    if (overflow) {
                        marquee.start()
                        if (root.playbackStalled)
                            marquee.pause()
                    } else {
                        lineRoot.x = Math.max(0, (cell.width - textW) / 2)
                    }
                }

                onTokenCountChanged: {
                    relayout()
                    startKaraoke()
                }
                onTextWChanged: relayout()
                onWidthChanged: relayout()
                onIsCurChanged: startKaraoke()
                Component.onCompleted: {
                    relayout()
                    startKaraoke()
                }

                // 超宽歌词：从头部向左滚动，滚到全部展示完就停住，不循环
                SequentialAnimation {
                    id: marquee
                    PauseAnimation { duration: 700 }
                    NumberAnimation {
                        target: lineRoot
                        property: "x"
                        from: 0
                        to: cell.width - cell.textW
                        duration: cell.marqueeMs
                        easing.type: Easing.Linear
                    }
                }
            }
        }

        // 播放进度条：钉在组件最底部
        ProgressBar {
            id: progressBar
            // SMTC 可用就用 SMTC 进度；否则用歌词渠道自带的进度（若有）
            visible: root.showProgress && backend.hasProgress
                     && (root.smtcUsable || backend.lyricProgressAvailable)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 4
            value: backend.progress

            Behavior on value {
                NumberAnimation { duration: 400; easing.type: Easing.Linear }
            }
        }
    }

    // 回退：有内容但不是多行歌词时，单行显示
    Quick.Text {
        anchors.centerIn: parent
        width: parent.width
        visible: !root.hasLyrics && backend.lyricStatus === "ok"
        text: backend.lyricText
        horizontalAlignment: Quick.Text.AlignHCenter
        elide: Quick.Text.ElideRight
        color: root.fgColor
        font.pixelSize: root.mainSize
        font.weight: Font.DemiBold
    }

    // 等待提示
    Quick.Text {
        anchors.centerIn: parent
        width: parent.width
        visible: backend.lyricStatus !== "ok" && !root.hasLyrics
        text: qsTr("等待音乐软件侧传输歌词...")
        horizontalAlignment: Quick.Text.AlignHCenter
        wrapMode: Quick.Text.Wrap
        color: root.hasCover ? root.fgColor : Theme.currentTheme.colors.textSecondaryColor
        font.pixelSize: 13
    }
}
