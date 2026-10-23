object RADESettingsForm: TRADESettingsForm
  Left = 0
  Top = 0
  Caption = 'RADEssentials - Settings'
  ClientHeight = 180
  ClientWidth = 380
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object LblShortcutFormatX: TLabel
    Left = 24
    Top = 24
    Width = 103
    Height = 15
    Caption = 'Format X Shortcut:'
  end
  object EdtShortcutFormatX: TEdit
    Left = 160
    Top = 21
    Width = 185
    Height = 23
    TabOrder = 0
    Text = 'Ctrl+Alt+F'
  end
  object LblShortcutPDF: TLabel
    Left = 24
    Top = 64
    Width = 108
    Height = 15
    Caption = 'PDF Viewer Shortcut:'
  end
  object EdtShortcutPDF: TEdit
    Left = 160
    Top = 61
    Width = 185
    Height = 23
    TabOrder = 1
    Text = 'Ctrl+Alt+P'
  end
  object BtnSave: TButton
    Left = 189
    Top = 125
    Width = 75
    Height = 25
    Caption = 'Save'
    Default = True
    TabOrder = 2
    OnClick = BtnSaveClick
  end
  object LblShortcutInstructions: TLabel
    Left = 24
    Top = 98
    Width = 225
    Height = 15
    Caption = 'Click a shortcut field, then press the keys.'
  end
  object BtnCancel: TButton
    Left = 270
    Top = 125
    Width = 75
    Height = 25
    Caption = 'Cancel'
    Cancel = True
    ModalResult = 2
    TabOrder = 3
  end
end
