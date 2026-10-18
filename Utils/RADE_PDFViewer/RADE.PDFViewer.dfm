object RADEPDFViewerForm: TRADEPDFViewerForm
  Left = 0
  Top = 0
  Caption = 'PDF Studio'
  ClientHeight = 720
  ClientWidth = 1100
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poDefault
  BorderStyle = bsSizeable
  OnClose = FormClose
  OnCreate = FormCreate
  TextHeight = 15
  object PanelTopBar: TPanel
    Left = 0
    Top = 0
    Width = 1100
    Height = 50
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object LblRecent: TLabel
      Left = 12
      Top = 17
      Width = 42
      Height = 15
      Caption = 'Recent:'
    end
    object BtnOpenPDF: TButton
      Left = 352
      Top = 11
      Width = 90
      Height = 28
      Caption = 'Open PDFs...'
      TabOrder = 0
      OnClick = BtnOpenPDFClick
    end
    object BtnMinimize: TButton
      Left = 915
      Top = 11
      Width = 75
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'Close tab'
      TabOrder = 1
      OnClick = BtnMinimizeClick
    end
    object BtnClose: TButton
      Left = 1005
      Top = 11
      Width = 75
      Height = 28
      Anchors = [akTop, akRight]
      Caption = 'Hide'
      TabOrder = 2
      OnClick = BtnCloseClick
    end
    object CmbRecent: TComboBox
      Left = 62
      Top = 13
      Width = 275
      Height = 23
      Anchors = [akLeft, akTop]
      Style = csDropDownList
      TabOrder = 3
      OnSelect = CmbRecentSelect
    end
  end
  object PanelSidebar: TPanel
    Left = 0
    Top = 50
    Width = 230
    Height = 644
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    object LblBookmarks: TLabel
      Left = 10
      Top = 8
      Width = 105
      Height = 24
      Caption = 'RECENT FILES'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object TreeBookmarks: TTreeView
      Left = 0
      Top = 32
      Width = 230
      Height = 612
      Align = alClient
      Anchors = [akLeft, akTop, akRight, akBottom]
      Indent = 18
      ReadOnly = True
      TabOrder = 0
    end
  end
  object SplitterSidebar: TSplitter
    Left = 230
    Top = 50
    Width = 5
    Height = 644
    Align = alLeft
  end
  object PageControlPDFs: TPageControl
    Left = 235
    Top = 50
    Width = 865
    Height = 644
    Align = alClient
    TabOrder = 2
  end
end
