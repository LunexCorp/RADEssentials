object RADEPDFViewerFrame: TRADEPDFViewerFrame
  Left = 0
  Top = 0
  Width = 560
  Height = 720
  object PanelTopBar: TPanel
    Left = 0
    Top = 0
    Width = 560
    Height = 44
    Align = alTop
    BevelOuter = bvNone
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object LblTitle: TLabel
      Left = 12
      Top = 14
      Width = 64
      Height = 18
      Caption = 'PDF Viewer'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object CmbRecent: TComboBox
      Left = 80
      Top = 10
      Width = 170
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnSelect = CmbRecentSelect
    end
    object BtnOpenPDF: TButton
      Left = 256
      Top = 7
      Width = 78
      Height = 29
      Caption = 'Open...'
      TabOrder = 1
      OnClick = BtnOpenPDFClick
    end
    object BtnMinimize: TButton
      Left = 430
      Top = 7
      Width = 70
      Height = 29
      Anchors = [akTop, akRight]
      Caption = 'Close tab'
      TabOrder = 2
      OnClick = BtnMinimizeClick
    end
  end
  object PageControlPDFs: TPageControl
    Left = 0
    Top = 44
    Width = 560
    Height = 650
    Align = alClient
    TabOrder = 1
  end
end
