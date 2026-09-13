import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RinUI
import ClassWidgets.Plugins

SettingsLayout {
    id: root

    // 主歌词字号（px）
    property int mainSizeValue: 13
    onMainSizeValueChanged: settings.lyric_font_size = mainSizeValue

    // 上一句 / 下一句字号（px）
    property int subSizeValue: 10
    onSubSizeValueChanged: settings.sub_font_size = subSizeValue

    // 配色方案：auto / light / dark / vivid / soft / tinted / theme / white / black / custom
    property string colorModeValue: "auto"
    onColorModeValueChanged: settings.lyric_color = colorModeValue

    // 自定义颜色（#RRGGBB）
    property string customColorValue: "#ffffff"
    onCustomColorValueChanged: settings.lyric_color_custom = customColorValue

    // 封面背景
    property bool showCoverValue: true
    onShowCoverValueChanged: settings.show_cover = showCoverValue

    property bool showProgressValue: true
    onShowProgressValueChanged: settings.show_progress = showProgressValue

    // 逐字高亮
    property bool karaokeValue: true
    onKaraokeValueChanged: settings.karaoke_enabled = karaokeValue

    // 歌词弹出显示
    property bool autoShowValue: true
    onAutoShowValueChanged: settings.auto_show = autoShowValue

    // 未核验时也显示进度
    property bool allowUnverifiedValue: false
    onAllowUnverifiedValueChanged: settings.progress_unverified = allowUnverifiedValue

    Component.onCompleted: {
        mainSizeValue = settings.lyric_font_size !== undefined ? settings.lyric_font_size : 13
        subSizeValue = settings.sub_font_size !== undefined ? settings.sub_font_size : 10
        colorModeValue = settings.lyric_color !== undefined ? settings.lyric_color : "auto"
        customColorValue = settings.lyric_color_custom !== undefined ? settings.lyric_color_custom : "#ffffff"
        showCoverValue = settings.show_cover !== undefined ? settings.show_cover : true
        showProgressValue = settings.show_progress !== undefined ? settings.show_progress : true
        autoShowValue = settings.auto_show !== undefined ? settings.auto_show : true
        allowUnverifiedValue = settings.progress_unverified !== undefined ? settings.progress_unverified : false
        karaokeValue = settings.karaoke_enabled !== undefined ? settings.karaoke_enabled : true
    }

    SettingCard {
        Layout.fillWidth: true
        title: "封面背景"
        description: "从系统媒体会话（SMTC）读取当前歌曲的专辑封面，模糊后作为组件背景。"

        Switch {
            checked: root.showCoverValue
            onCheckedChanged: root.showCoverValue = checked
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "主歌词字号"
        description: "当前这一句歌词的字号（px）。"

        RowLayout {
            spacing: 8
            Button {
                text: "−"
                implicitWidth: 36
                onClicked: mainSizeValue = Math.max(8, mainSizeValue - 1)
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignHCenter
                text: mainSizeValue + " px"
            }
            Button {
                text: "+"
                implicitWidth: 36
                onClicked: mainSizeValue = Math.min(40, mainSizeValue + 1)
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "上/下一句字号"
        description: "上一句、下一句歌词的字号（px），通常比主歌词小。"

        RowLayout {
            spacing: 8
            Button {
                text: "−"
                implicitWidth: 36
                onClicked: subSizeValue = Math.max(6, subSizeValue - 1)
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignHCenter
                text: subSizeValue + " px"
            }
            Button {
                text: "+"
                implicitWidth: 36
                onClicked: subSizeValue = Math.min(40, subSizeValue + 1)
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "歌词配色方案"
        description: "「自适应 / 鲜艳 / 柔和 / 偏色」都取自封面的主色调，会根据封面的明暗自动选用深色或浅色文字。"

        ColumnLayout {
            spacing: 10
            Layout.fillWidth: true

            RowLayout {
                spacing: 12
                RadioButton {
                    text: "自适应"
                    checked: root.colorModeValue === "auto"
                    onCheckedChanged: if (checked) root.colorModeValue = "auto"
                }
                RadioButton {
                    text: "深色"
                    checked: root.colorModeValue === "dark"
                    onCheckedChanged: if (checked) root.colorModeValue = "dark"
                }
                RadioButton {
                    text: "浅色"
                    checked: root.colorModeValue === "light"
                    onCheckedChanged: if (checked) root.colorModeValue = "light"
                }
            }

            RowLayout {
                spacing: 12
                RadioButton {
                    text: "鲜艳"
                    checked: root.colorModeValue === "vivid"
                    onCheckedChanged: if (checked) root.colorModeValue = "vivid"
                }
                RadioButton {
                    text: "柔和"
                    checked: root.colorModeValue === "soft"
                    onCheckedChanged: if (checked) root.colorModeValue = "soft"
                }
                RadioButton {
                    text: "偏色"
                    checked: root.colorModeValue === "tinted"
                    onCheckedChanged: if (checked) root.colorModeValue = "tinted"
                }
            }

            RowLayout {
                spacing: 12
                RadioButton {
                    text: "跟随主题"
                    checked: root.colorModeValue === "theme"
                    onCheckedChanged: if (checked) root.colorModeValue = "theme"
                }
                RadioButton {
                    text: "自定义"
                    checked: root.colorModeValue === "custom"
                    onCheckedChanged: if (checked) root.colorModeValue = "custom"
                }
            }

            RowLayout {
                spacing: 10

                Rectangle {
                    width: 28
                    height: 28
                    radius: 6
                    border.width: 1
                    border.color: "#888888"
                    color: root.customColorValue
                }

                TextField {
                    id: colorField
                    Layout.preferredWidth: 140
                    placeholderText: "#RRGGBB"
                    text: root.customColorValue
                    selectByMouse: true
                    onEditingFinished: {
                        var v = text.trim()
                        if (v.charAt(0) !== "#")
                            v = "#" + v
                        root.customColorValue = v
                    }
                }

                // 常用预设色
                Repeater {
                    model: ["#ffffff", "#000000", "#ffd400", "#ff5c8a", "#46cea3", "#4aa3ff"]
                    delegate: Rectangle {
                        width: 22
                        height: 22
                        radius: 4
                        border.width: 1
                        border.color: "#888888"
                        color: modelData
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.customColorValue = modelData
                                root.colorModeValue = "custom"
                                colorField.text = modelData
                            }
                        }
                    }
                }
            }
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "显示播放进度条"
        description: "在歌词下方显示播放进度条；拿不到歌曲进度时会自动隐藏。"

        Switch {
            checked: root.showProgressValue
            onCheckedChanged: root.showProgressValue = checked
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "未核验时也使用 SMTC 功能"
        description: "默认关闭：只要没确认 SMTC 与歌词是同一首歌，就停用播放进度条、封面背景、" +
                     "以及逐字同步（改为按节奏估算），并释放封面等占用，只保留歌词自身能提供的效果。" +
                     "打开后会退回到「没确认也用」的旧行为。"

        Switch {
            checked: root.allowUnverifiedValue
            onCheckedChanged: root.allowUnverifiedValue = checked
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "逐字高亮（读到哪儿亮到哪儿）"
        description: "仅为动画效果：速度按上一句的节奏自适应估算，实际演唱可能比它提前或延后。" +
                     "关闭后当前歌词整行保持满亮度。"

        Switch {
            checked: root.karaokeValue
            onCheckedChanged: root.karaokeValue = checked
        }
    }

    SettingCard {
        Layout.fillWidth: true
        title: "歌词弹出显示"
        description: "识别到歌词时自动弹出展示，类似灵动通知。" +
                     "隐藏时机：歌曲暂停或停止约 10 秒后自动收起（恢复播放会重新弹出）；" +
                     "若拿不到系统播放状态，则改为长时间没有新歌词后收起。"

        Switch {
            checked: root.autoShowValue
            onCheckedChanged: root.autoShowValue = checked
        }
    }
}
