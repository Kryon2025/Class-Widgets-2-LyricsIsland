import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RinUI
import ClassWidgets.Plugins

SettingsLayout {
    id: root

    // 原文字号（px）
    property int lyricSizeValue: 16
    onLyricSizeValueChanged: settings.lyric_font_size = lyricSizeValue

    // 译文字号（px）
    property int extraSizeValue: 12
    onExtraSizeValueChanged: settings.extra_font_size = extraSizeValue

    // 逐字动画模式：off=关闭 / float=上浮
    property string animModeValue: "off"
    onAnimModeValueChanged: settings.anim_mode = animModeValue

    // 滚动时长（秒）：长歌词从右端滚到末字停在行末的总时长
    property int scrollSecondsValue: 8
    onScrollSecondsValueChanged: settings.scroll_seconds = scrollSecondsValue

    // 滚动前停顿（秒）
    property real scrollDelayValue: 0.5
    onScrollDelayValueChanged: settings.scroll_delay = scrollDelayValue

    // 灵动显示：有歌词自动弹出，无歌词自动隐藏
    property bool autoShowValue: true
    onAutoShowValueChanged: settings.auto_show = autoShowValue

    // 歌词颜色：white=白色 / black=黑色 / theme=跟随主题
    property string lyricColorValue: "white"
    onLyricColorValueChanged: settings.lyric_color = lyricColorValue

    // 一次性读取持久化设置（旧实例可能缺少新键，缺省回退默认值）
    Component.onCompleted: {
        lyricSizeValue = settings.lyric_font_size !== undefined ? settings.lyric_font_size : 16
        extraSizeValue = settings.extra_font_size !== undefined ? settings.extra_font_size : 12
        animModeValue = settings.anim_mode === "float" ? "float" : "off"
        scrollSecondsValue = settings.scroll_seconds !== undefined ? settings.scroll_seconds : 8
        scrollDelayValue = settings.scroll_delay !== undefined ? settings.scroll_delay : 0.5
        autoShowValue = settings.auto_show !== undefined ? settings.auto_show : true
        lyricColorValue = settings.lyric_color !== undefined ? settings.lyric_color : "white"
    }

    SettingCard {
        Layout.fillWidth: true
        title: "原文字号"
        description: "当前歌词的字体大小（px），组件尺寸保持不变，文字过长时自动省略。"

        RowLayout {
            spacing: 8
            Button {
                text: "−"
                implicitWidth: 36
                onClicked: lyricSizeValue = Math.max(12, lyricSizeValue - 1)
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignHCenter
                text: lyricSizeValue + " px"
            }
            Button {
                text: "+"
                implicitWidth: 36
                onClicked: lyricSizeValue = Math.min(28, lyricSizeValue + 1)
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "译文字号"
        description: "译文（附加歌词）的字体大小（px），组件尺寸保持不变。"

        RowLayout {
            spacing: 8
            Button {
                text: "−"
                implicitWidth: 36
                onClicked: extraSizeValue = Math.max(10, extraSizeValue - 1)
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignHCenter
                text: extraSizeValue + " px"
            }
            Button {
                text: "+"
                implicitWidth: 36
                onClicked: extraSizeValue = Math.min(24, extraSizeValue + 1)
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "歌词颜色"
        description: "主歌词字体颜色。桌面歌词常用白色，可自由选择。"

        RowLayout {
            spacing: 12

            RadioButton {
                text: "白色"
                checked: root.lyricColorValue === "white"
                onCheckedChanged: {
                    if (checked) root.lyricColorValue = "white"
                }
            }
            RadioButton {
                text: "黑色"
                checked: root.lyricColorValue === "black"
                onCheckedChanged: {
                    if (checked) root.lyricColorValue = "black"
                }
            }
            RadioButton {
                text: "跟随主题"
                checked: root.lyricColorValue === "theme"
                onCheckedChanged: {
                    if (checked) root.lyricColorValue = "theme"
                }
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "滚动时长"
        description: "歌词或译文过长时，自动从右端顶格向左滚动，最后一个字到达行末即停；此处为滚完的总时长（秒）。"

        RowLayout {
            spacing: 8
            Button {
                text: "−"
                implicitWidth: 36
                onClicked: scrollSecondsValue = Math.max(3, scrollSecondsValue - 1)
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignHCenter
                text: scrollSecondsValue + " 秒"
            }
            Button {
                text: "+"
                implicitWidth: 36
                onClicked: scrollSecondsValue = Math.min(30, scrollSecondsValue + 1)
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "滚动前停顿"
        description: "长歌词开始滚动前在起点停留的时间（秒），便于先看清歌词开头。"

        RowLayout {
            spacing: 8
            Button {
                text: "−"
                implicitWidth: 36
                onClicked: scrollDelayValue = Math.max(0, Math.round((scrollDelayValue - 0.1) * 10) / 10)
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignHCenter
                text: scrollDelayValue.toFixed(1) + " 秒"
            }
            Button {
                text: "+"
                implicitWidth: 36
                onClicked: scrollDelayValue = Math.min(3, Math.round((scrollDelayValue + 0.1) * 10) / 10)
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "歌词弹出显示"
        description: "开启后，识别到歌词时组件自动弹出展示，无歌词时自动隐藏（类似灵动通知）。"

        Switch {
            checked: settings.auto_show !== undefined ? settings.auto_show : true
            onCheckedChanged: settings.auto_show = checked
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "逐字动画"
        description: "换段时上一段逐字上浮淡出、下一段逐字呈现的效果。"

        RowLayout {
            spacing: 16

            RadioButton {
                text: "关闭"
                checked: root.animModeValue === "off"
                onCheckedChanged: {
                    if (checked) root.animModeValue = "off"
                }
            }
            RadioButton {
                text: "上浮"
                checked: root.animModeValue === "float"
                onCheckedChanged: {
                    if (checked) root.animModeValue = "float"
                }
            }
        }
    }
}
