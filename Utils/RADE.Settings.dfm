object RADESettingsForm: TRADESettingsForm
  Left = 0
  Top = 0
  Caption = 'RADEssentials Settings'
  ClientHeight = 412
  ClientWidth = 560
  Color = clWhite
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  BorderStyle = bsDialog
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object PanelHeader: TPanel
    Left = 0
    Top = 0
    Width = 560
    Height = 94
    Align = alTop
    BevelOuter = bvNone
    Color = 3618875
    ParentBackground = False
    TabOrder = 0
    object LblTitle: TLabel
      Left = 24
      Top = 18
      Width = 280
      Height = 32
      Caption = 'Preferences'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWhite
      Font.Height = -19
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblSubtitle: TLabel
      Left = 25
      Top = 54
      Width = 480
      Height = 20
      Caption = 'Customize your RAD Studio workflow'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 15395562
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
  end
  object PanelFooter: TPanel
    Left = 0
    Top = 344
    Width = 560
    Height = 68
    Align = alBottom
    BevelOuter = bvNone
    Color = 15987699
    ParentBackground = False
    TabOrder = 1
    object BtnSave: TButton
      Left = 374
      Top = 17
      Width = 82
      Height = 32
      Anchors = [akTop, akRight]
      Caption = 'Save'
      Default = True
      TabOrder = 0
      OnClick = BtnSaveClick
    end
    object BtnCancel: TButton
      Left = 466
      Top = 17
      Width = 78
      Height = 32
      Anchors = [akTop, akRight]
      Caption = 'Cancel'
      Cancel = True
      ModalResult = 2
      TabOrder = 1
    end
  end
  object PanelShortcuts: TPanel
    Left = 0
    Top = 94
    Width = 560
    Height = 250
    Align = alClient
    BevelOuter = bvNone
    Color = clWhite
    ParentBackground = False
    TabOrder = 2
    object ShapeFormatX: TShape
      Left = 20
      Top = 48
      Width = 520
      Height = 48
      Brush.Color = clWhite
      Pen.Color = 14804702
      Shape = stRoundRect
    end
    object ShapePDF: TShape
      Left = 20
      Top = 105
      Width = 520
      Height = 48
      Brush.Color = clWhite
      Pen.Color = 14804702
      Shape = stRoundRect
    end
    object ShapeSearch: TShape
      Left = 20
      Top = 162
      Width = 520
      Height = 48
      Brush.Color = clWhite
      Pen.Color = 14804702
      Shape = stRoundRect
    end
    object LblShortcutInstructions: TLabel
      Left = 24
      Top = 16
      Width = 500
      Height = 22
      Caption = 'KEYBOARD SHORTCUTS'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 8618883
      Font.Height = -11
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblShortcutFormatX: TLabel
      Left = 36
      Top = 54
      Width = 230
      Height = 19
      Caption = 'Format Code'
    end
    object LblShortcutPDF: TLabel
      Left = 36
      Top = 111
      Width = 230
      Height = 19
      Caption = 'PDF Viewer'
    end
    object LblShortcutSearch: TLabel
      Left = 36
      Top = 168
      Width = 230
      Height = 19
      Caption = 'Search'
    end
    object LblFormatDescription: TLabel
      Left = 36
      Top = 74
      Width = 230
      Height = 16
      Caption = 'Format the current source file'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 8618883
      Font.Height = -10
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object LblPDFDescription: TLabel
      Left = 36
      Top = 131
      Width = 230
      Height = 16
      Caption = 'Open and focus the PDF Viewer pane'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 8618883
      Font.Height = -10
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object LblSearchDescription: TLabel
      Left = 36
      Top = 188
      Width = 230
      Height = 16
      Caption = 'Search RAD Studio actions and content'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 8618883
      Font.Height = -10
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
    end
    object EdtShortcutFormatX: TEdit
      Left = 300
      Top = 58
      Width = 224
      Height = 27
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 3618875
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 0
      Text = 'Ctrl+Alt+F'
    end
    object EdtShortcutPDF: TEdit
      Left = 300
      Top = 115
      Width = 224
      Height = 27
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 3618875
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 1
      Text = 'Ctrl+Alt+P'
    end
    object EdtShortcutSearch: TEdit
      Left = 300
      Top = 172
      Width = 224
      Height = 27
      Font.Charset = DEFAULT_CHARSET
      Font.Color = 3618875
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 2
      Text = 'Ctrl+Shift+A'
    end
  end
end
