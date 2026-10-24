unit RADE.PDFViewer;

interface

uses
  Winapi.Windows, Winapi.WebView2, System.SysUtils, System.Classes,
  System.IOUtils, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Edge;

type
  TRADEPDFViewerFrame = class(TFrame)
    PanelTopBar: TPanel;
    LblTitle: TLabel;
    BtnOpenPDF: TButton;
    BtnMinimize: TButton;
    CmbRecent: TComboBox;
    PageControlPDFs: TPageControl;
    procedure BtnOpenPDFClick(Sender: TObject);
    procedure BtnMinimizeClick(Sender: TObject);
    procedure CmbRecentSelect(Sender: TObject);
  private
    BtnZoomOut, BtnZoomIn, BtnWelcomeOpen: TButton;
    PanelWelcome, PanelStatus: TPanel;
    LblWelcome, LblWelcomeSubtitle, LblStatus: TLabel;
    FRecentFiles: TStringList;
    procedure ActiveTabChanged(Sender: TObject);
    procedure BrowserCreateCompleted(Sender: TCustomEdgeBrowser; AResult: HResult);
    procedure BrowserNavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure CloseActiveTab;
    function GetActiveBrowser: TEdgeBrowser;
    function GetRecentListPath: string;
    procedure LoadRecentList;
    procedure RefreshRecentList;
    procedure AddToRecentList(const AFileName: string);
    procedure OpenPDFFile(const AFileName: string);
    function PdfFileUrl(const AFileName: string): string;
    procedure UpdateWelcome;
    procedure SetStatus(const AText: string);
    procedure ZoomBy(ADelta: Double);
    procedure ZoomOutClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
  public
    destructor Destroy; override;
    procedure InitializeViewer;
    procedure ShutdownViewer;
  end;

  TRADEPDFViewerEditorHost = class
  public
    class procedure ShowViewer;
  end;

implementation

{$R *.dfm}

class procedure TRADEPDFViewerEditorHost.ShowViewer;
begin
  MessageDlg('PDF Viewer is temporarily unavailable while the viewer is being repaired.',
    mtInformation, [mbOK], 0);
end;

procedure TRADEPDFViewerFrame.ShutdownViewer;
var
  I: Integer;
  LBrowser: TEdgeBrowser;
begin
  for I := 0 to PageControlPDFs.PageCount - 1 do
    if PageControlPDFs.Pages[I].FindComponent('PdfBrowser') is TEdgeBrowser then
    begin
      LBrowser := TEdgeBrowser(PageControlPDFs.Pages[I].FindComponent('PdfBrowser'));
      LBrowser.OnCreateWebViewCompleted := nil;
      LBrowser.OnNavigationCompleted := nil;
      LBrowser.CloseWebView;
    end;
end;

destructor TRADEPDFViewerFrame.Destroy;
begin
  ShutdownViewer;
  FreeAndNil(FRecentFiles);
  inherited Destroy;
end;

function TRADEPDFViewerFrame.GetRecentListPath: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'RadeEssentials'),
    'recent-pdfs.txt');
end;

procedure TRADEPDFViewerFrame.LoadRecentList;
var
  I: Integer;
begin
  FRecentFiles.Clear;
  if TFile.Exists(GetRecentListPath) then
    try
      FRecentFiles.LoadFromFile(GetRecentListPath, TEncoding.UTF8);
    except
      FRecentFiles.Clear;
    end;
  for I := FRecentFiles.Count - 1 downto 0 do
    if not TFile.Exists(FRecentFiles[I]) then
      FRecentFiles.Delete(I);
  RefreshRecentList;
end;

procedure TRADEPDFViewerFrame.RefreshRecentList;
var
  I: Integer;
begin
  CmbRecent.Items.BeginUpdate;
  try
    CmbRecent.Items.Clear;
    for I := 0 to FRecentFiles.Count - 1 do
      CmbRecent.Items.Add(ExtractFileName(FRecentFiles[I]));
    if CmbRecent.Items.Count > 0 then
      CmbRecent.ItemIndex := 0;
  finally
    CmbRecent.Items.EndUpdate;
  end;
end;

procedure TRADEPDFViewerFrame.AddToRecentList(const AFileName: string);
var
  LPath: string;
  LIndex: Integer;
begin
  LPath := TPath.GetFullPath(AFileName);
  LIndex := FRecentFiles.IndexOf(LPath);
  if LIndex >= 0 then
    FRecentFiles.Delete(LIndex);
  FRecentFiles.Insert(0, LPath);
  while FRecentFiles.Count > 15 do
    FRecentFiles.Delete(FRecentFiles.Count - 1);
  ForceDirectories(ExtractFileDir(GetRecentListPath));
  try
    FRecentFiles.SaveToFile(GetRecentListPath, TEncoding.UTF8);
  except
    SetStatus('PDF opened, but the recent-file list could not be saved.');
  end;
  RefreshRecentList;
end;

procedure TRADEPDFViewerFrame.BtnOpenPDFClick(Sender: TObject);
var
  LDialog: TOpenDialog;
  LFile: string;
begin
  LDialog := TOpenDialog.Create(Self);
  try
    LDialog.Title := 'Open PDF documents';
    LDialog.Filter := 'PDF documents (*.pdf)|*.pdf';
    LDialog.Options := [ofFileMustExist, ofPathMustExist, ofAllowMultiSelect];
    if LDialog.Execute then
      for LFile in LDialog.Files do
        OpenPDFFile(LFile);
  finally
    LDialog.Free;
  end;
end;

procedure TRADEPDFViewerFrame.OpenPDFFile(const AFileName: string);
var
  I: Integer;
  LPath, LUserData: string;
  LTab: TTabSheet;
  LBrowser: TEdgeBrowser;
begin
  if not TFile.Exists(AFileName) then
  begin
    SetStatus('That PDF file can no longer be found.');
    Exit;
  end;
  LPath := TPath.GetFullPath(AFileName);
  for I := 0 to PageControlPDFs.PageCount - 1 do
    if SameText(PageControlPDFs.Pages[I].Hint, LPath) then
    begin
      PageControlPDFs.ActivePage := PageControlPDFs.Pages[I];
      AddToRecentList(LPath);
      Exit;
    end;

  AddToRecentList(LPath);
  LTab := TTabSheet.Create(PageControlPDFs);
  LTab.PageControl := PageControlPDFs;
  LTab.Caption := ExtractFileName(LPath);
  LTab.Hint := LPath;

  LBrowser := TEdgeBrowser.Create(LTab);
  LBrowser.Name := 'PdfBrowser';
  LBrowser.OnCreateWebViewCompleted := BrowserCreateCompleted;
  LBrowser.OnNavigationCompleted := BrowserNavigationCompleted;
  LUserData := TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
    'RADEssentials\PDFWebView2');
  if not ForceDirectories(LUserData) and not TDirectory.Exists(LUserData) then
  begin
    SetStatus('Could not create the WebView2 data folder: ' + LUserData);
    LTab.Free;
    Exit;
  end;
  LBrowser.UserDataFolder := LUserData;
  LBrowser.Parent := LTab;
  LBrowser.Align := alClient;

  PageControlPDFs.ActivePage := LTab;
  SetStatus('Loading ' + ExtractFileName(LPath) + '...');
  UpdateWelcome;
  LBrowser.Navigate(PdfFileUrl(LPath));
end;

function TRADEPDFViewerFrame.PdfFileUrl(const AFileName: string): string;
var
  LFileName: string;
  LBytes: TBytes;
  LByte: Byte;
  LBuilder: TStringBuilder;
begin
  LFileName := ExtractFileName(AFileName);
  LBytes := TEncoding.UTF8.GetBytes(LFileName);
  LBuilder := TStringBuilder.Create('https://rade-pdf.local/');
  try
    for LByte in LBytes do
      if ((LByte >= Ord('A')) and (LByte <= Ord('Z'))) or
        ((LByte >= Ord('a')) and (LByte <= Ord('z'))) or
        ((LByte >= Ord('0')) and (LByte <= Ord('9'))) or
        (LByte = Ord('-')) or (LByte = Ord('.')) or
        (LByte = Ord('_')) or (LByte = Ord('~')) or
        (LByte = Ord('/')) then
        LBuilder.Append(Char(LByte))
      else
        LBuilder.Append('%').Append(IntToHex(LByte, 2));
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

procedure TRADEPDFViewerFrame.CmbRecentSelect(Sender: TObject);
begin
  if (CmbRecent.ItemIndex >= 0) and (CmbRecent.ItemIndex < FRecentFiles.Count) then
    OpenPDFFile(FRecentFiles[CmbRecent.ItemIndex]);
end;

function TRADEPDFViewerFrame.GetActiveBrowser: TEdgeBrowser;
begin
  Result := nil;
  if PageControlPDFs.ActivePage <> nil then
    Result := PageControlPDFs.ActivePage.FindComponent('PdfBrowser') as TEdgeBrowser;
end;

procedure TRADEPDFViewerFrame.ActiveTabChanged(Sender: TObject);
var
  LBrowser: TEdgeBrowser;
begin
  if PageControlPDFs.ActivePage <> nil then
  begin
    LBrowser := GetActiveBrowser;
    if (LBrowser <> nil) and LBrowser.WebViewCreated then
      SetStatus('Ready: ' + PageControlPDFs.ActivePage.Caption)
    else if (LBrowser <> nil) and (LBrowser.LastErrorCode < 0) then
      SetStatus(Format('WebView2 could not start (HRESULT 0x%s).',
        [IntToHex(Cardinal(LBrowser.LastErrorCode), 8)]))
    else
      SetStatus('Loading ' + PageControlPDFs.ActivePage.Caption + '...');
  end;
  UpdateWelcome;
end;

procedure TRADEPDFViewerFrame.BrowserCreateCompleted(Sender: TCustomEdgeBrowser;
  AResult: HResult);
var
  LTab: TTabSheet;
  LWebView3: ICoreWebView2_3;
  LResult: HResult;
begin
  if AResult < 0 then
  begin
    if Sender.Owner = PageControlPDFs.ActivePage then
      SetStatus(Format('WebView2 could not start (HRESULT 0x%s). Check the WebView2 Runtime and access to %s.',
        [IntToHex(Cardinal(AResult), 8),
        TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'),
          'RADEssentials\PDFWebView2')]));
    Exit;
  end;
  LTab := Sender.Owner as TTabSheet;
  if not Supports(Sender.DefaultInterface, ICoreWebView2_3, LWebView3) then
  begin
    if LTab = PageControlPDFs.ActivePage then
      SetStatus('The installed WebView2 Runtime is too old to display local PDFs. Update the Evergreen Runtime.');
    Exit;
  end;
  LResult := LWebView3.SetVirtualHostNameToFolderMapping(
    'rade-pdf.local', PChar(ExtractFileDir(LTab.Hint)),
    COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
  if LResult < 0 then
  begin
    if LTab = PageControlPDFs.ActivePage then
      SetStatus(Format('Could not prepare %s for viewing (HRESULT 0x%s).',
        [LTab.Caption, IntToHex(Cardinal(LResult), 8)]));
    Exit;
  end;
end;

procedure TRADEPDFViewerFrame.BrowserNavigationCompleted(Sender: TCustomEdgeBrowser;
  IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
var
  LTab: TTabSheet;
begin
  LTab := Sender.Owner as TTabSheet;
  if LTab = PageControlPDFs.ActivePage then
    if IsSuccess then
      SetStatus('Ready: ' + LTab.Caption)
    else
      SetStatus(Format('Could not display %s (WebView2 error %d). Check that the file is a readable PDF.',
        [LTab.Caption, Ord(WebErrorStatus)]));
end;

procedure TRADEPDFViewerFrame.UpdateWelcome;
begin
  PanelWelcome.Visible := PageControlPDFs.PageCount = 0;
  if PageControlPDFs.PageCount = 0 then
    SetStatus('Open a PDF to get started.');
end;

procedure TRADEPDFViewerFrame.CloseActiveTab;
var
  LTab: TTabSheet;
begin
  LTab := PageControlPDFs.ActivePage;
  if LTab = nil then
    Exit;
  LTab.Free;
  if PageControlPDFs.PageCount = 0 then
    UpdateWelcome;
end;

procedure TRADEPDFViewerFrame.BtnMinimizeClick(Sender: TObject);
begin
  CloseActiveTab;
end;

procedure TRADEPDFViewerFrame.ZoomBy(ADelta: Double);
var
  LBrowser: TEdgeBrowser;
  LZoom: Double;
begin
  LBrowser := GetActiveBrowser;
  if (LBrowser = nil) or not LBrowser.WebViewCreated then
    Exit;
  LZoom := LBrowser.ZoomFactor + ADelta;
  if LZoom < 0.5 then
    LZoom := 0.5
  else if LZoom > 3.0 then
    LZoom := 3.0;
  LBrowser.ZoomFactor := LZoom;
  SetStatus(Format('Zoom: %d%%', [Round(LZoom * 100)]));
end;

procedure TRADEPDFViewerFrame.ZoomOutClick(Sender: TObject);
begin
  ZoomBy(-0.1);
end;

procedure TRADEPDFViewerFrame.ZoomInClick(Sender: TObject);
begin
  ZoomBy(0.1);
end;

procedure TRADEPDFViewerFrame.SetStatus(const AText: string);
begin
  if LblStatus <> nil then
    LblStatus.Caption := AText;
end;

procedure TRADEPDFViewerFrame.InitializeViewer;
begin
  FRecentFiles := TStringList.Create;
  PageControlPDFs.OnChange := ActiveTabChanged;
  LblTitle.Caption := 'PDF Viewer';
  BtnOpenPDF.Caption := 'Open...';
  BtnMinimize.Caption := 'Close tab';
  BtnMinimize.Hint := 'Close current document';
  BtnMinimize.ShowHint := True;
  PanelTopBar.BevelOuter := bvNone;
  PanelTopBar.Color := clWhite;
  LblTitle.Font.Style := [fsBold];
  LblTitle.Font.Size := 12;
  LblTitle.Font.Color := RGB(40, 55, 75);
  BtnOpenPDF.Font.Style := [fsBold];
  PageControlPDFs.HotTrack := True;
  PageControlPDFs.TabPosition := tpTop;

  BtnZoomOut := TButton.Create(Self);
  BtnZoomOut.Parent := PanelTopBar;
  BtnZoomOut.SetBounds(ClientWidth - 215, 8, 30, 28);
  BtnZoomOut.Anchors := [akTop, akRight];
  BtnZoomOut.Caption := '-';
  BtnZoomOut.Hint := 'Zoom out';
  BtnZoomOut.ShowHint := True;
  BtnZoomOut.OnClick := ZoomOutClick;

  BtnZoomIn := TButton.Create(Self);
  BtnZoomIn.Parent := PanelTopBar;
  BtnZoomIn.SetBounds(ClientWidth - 181, 8, 30, 28);
  BtnZoomIn.Anchors := [akTop, akRight];
  BtnZoomIn.Caption := '+';
  BtnZoomIn.Hint := 'Zoom in';
  BtnZoomIn.ShowHint := True;
  BtnZoomIn.OnClick := ZoomInClick;

  PanelStatus := TPanel.Create(Self);
  PanelStatus.Parent := Self;
  PanelStatus.Align := alBottom;
  PanelStatus.Height := 26;
  PanelStatus.BevelOuter := bvNone;
  PanelStatus.Color := RGB(246, 247, 249);
  PanelStatus.Padding.Left := 12;
  PanelStatus.Padding.Right := 12;

  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := PanelStatus;
  LblStatus.Align := alClient;
  LblStatus.Layout := tlCenter;
  LblStatus.Font.Color := RGB(75, 85, 100);
  LblStatus.Caption := 'Open a PDF to get started.';

  PanelWelcome := TPanel.Create(Self);
  PanelWelcome.Parent := PageControlPDFs;
  PanelWelcome.Align := alClient;
  PanelWelcome.BevelOuter := bvNone;
  PanelWelcome.Padding.Top := 80;
  PanelWelcome.Color := clWhite;
  PanelWelcome.ParentBackground := False;

  LblWelcome := TLabel.Create(Self);
  LblWelcome.Parent := PanelWelcome;
  LblWelcome.Align := alTop;
  LblWelcome.Height := 64;
  LblWelcome.Alignment := taCenter;
  LblWelcome.Layout := tlCenter;
  LblWelcome.Font.Size := 22;
  LblWelcome.Font.Style := [fsBold];
  LblWelcome.Font.Color := RGB(40, 55, 75);
  LblWelcome.Caption := 'Your documents, in one place';

  LblWelcomeSubtitle := TLabel.Create(Self);
  LblWelcomeSubtitle.Parent := PanelWelcome;
  LblWelcomeSubtitle.Align := alTop;
  LblWelcomeSubtitle.Height := 44;
  LblWelcomeSubtitle.Alignment := taCenter;
  LblWelcomeSubtitle.Layout := tlCenter;
  LblWelcomeSubtitle.Font.Size := 10;
  LblWelcomeSubtitle.Font.Color := RGB(105, 115, 130);
  LblWelcomeSubtitle.Caption := 'Open a PDF to read, search, print, and move between documents.';

  BtnWelcomeOpen := TButton.Create(Self);
  BtnWelcomeOpen.Parent := PanelWelcome;
  BtnWelcomeOpen.Align := alTop;
  BtnWelcomeOpen.Height := 38;
  BtnWelcomeOpen.Margins.Left := 180;
  BtnWelcomeOpen.Margins.Right := 180;
  BtnWelcomeOpen.Margins.Top := 16;
  BtnWelcomeOpen.AlignWithMargins := True;
  BtnWelcomeOpen.Caption := 'Open PDF files';
  BtnWelcomeOpen.OnClick := BtnOpenPDFClick;

  LoadRecentList;
  UpdateWelcome;
end;

end.
