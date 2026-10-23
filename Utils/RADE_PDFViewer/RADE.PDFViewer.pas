unit RADE.PDFViewer;

interface

uses
  Winapi.Windows, Winapi.WebView2, System.SysUtils, System.Classes,
  System.IOUtils, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Edge, DockForm;

type
  TRADEPDFViewerForm = class(TDockableForm)
    PanelTopBar: TPanel;
    BtnOpenPDF: TButton;
    BtnMinimize: TButton;
    BtnClose: TButton;
    CmbRecent: TComboBox;
    LblRecent: TLabel;
    SplitterSidebar: TSplitter;
    PanelSidebar: TPanel;
    TreeBookmarks: TTreeView;
    LblBookmarks: TLabel;
    PageControlPDFs: TPageControl;
    procedure BtnOpenPDFClick(Sender: TObject);
    procedure BtnMinimizeClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure CmbRecentSelect(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    BtnZoomOut, BtnZoomIn, BtnWelcomeOpen: TButton;
    PanelWelcome, PanelStatus: TPanel;
    LblWelcome, LblStatus: TLabel;
    FRecentFiles: TStringList;
    procedure ActiveTabChanged(Sender: TObject);
    procedure BrowserCreateCompleted(Sender: TCustomEdgeBrowser; AResult: HResult);
    procedure BrowserNavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure CloseActiveTab;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function GetActiveBrowser: TEdgeBrowser;
    function GetRecentListPath: string;
    procedure LoadRecentList;
    procedure RecentClick(Sender: TObject);
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
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    class procedure ToggleViewer;
    class function IsOpen: Boolean;
  end;

procedure RADEPDFViewer_RegisterDock;
procedure RADEPDFViewer_FreeDock;

implementation

{$R *.dfm}

uses
  DeskUtil, ToolsAPI;

var
  GlobalPDFForm: TRADEPDFViewerForm = nil;
  GRegistered: Boolean;

procedure RADEPDFViewer_RegisterDock;
begin
  if GRegistered then
    Exit;
  RegisterFieldAddress('RADEPDFViewer', @GlobalPDFForm);
  RegisterDesktopFormClass(TRADEPDFViewerForm, 'RADEPDFViewer', 'RADEPDFViewer');
  GRegistered := True;
end;

procedure RADEPDFViewer_FreeDock;
begin
  if GRegistered then
  begin
    UnregisterFieldAddress(@GlobalPDFForm);
    GRegistered := False;
  end;
  FreeAndNil(GlobalPDFForm);
end;

constructor TRADEPDFViewerForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := 'PDF Studio';
  DeskSection := 'RADEPDFViewer';
  AutoSave := True;
  SaveStateNecessary := True;
  Constraints.MinWidth := 760;
  Constraints.MinHeight := 420;
end;

destructor TRADEPDFViewerForm.Destroy;
begin
  FreeAndNil(FRecentFiles);
  if GlobalPDFForm = Self then
    GlobalPDFForm := nil;
  inherited Destroy;
end;

class procedure TRADEPDFViewerForm.ToggleViewer;
begin
  if GlobalPDFForm = nil then
    GlobalPDFForm := TRADEPDFViewerForm.Create(Application);
  if GlobalPDFForm.Visible then
    GlobalPDFForm.Hide
  else if not GlobalPDFForm.Floating then
    GlobalPDFForm.ForceShow
  else
    GlobalPDFForm.Show;
  if GlobalPDFForm.Visible then
    FocusWindow(GlobalPDFForm);
end;

class function TRADEPDFViewerForm.IsOpen: Boolean;
begin
  Result := Assigned(GlobalPDFForm) and GlobalPDFForm.Visible;
end;

function TRADEPDFViewerForm.GetRecentListPath: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'RadeEssentials'),
    'recent-pdfs.txt');
end;

procedure TRADEPDFViewerForm.LoadRecentList;
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

procedure TRADEPDFViewerForm.RefreshRecentList;
var
  I: Integer;
  LNode: TTreeNode;
begin
  CmbRecent.Items.BeginUpdate;
  TreeBookmarks.Items.BeginUpdate;
  try
    CmbRecent.Items.Clear;
    TreeBookmarks.Items.Clear;
    for I := 0 to FRecentFiles.Count - 1 do
    begin
      CmbRecent.Items.Add(ExtractFileName(FRecentFiles[I]));
      LNode := TreeBookmarks.Items.Add(nil, ExtractFileName(FRecentFiles[I]));
      LNode.Data := Pointer(I + 1);
    end;
    if CmbRecent.Items.Count > 0 then
      CmbRecent.ItemIndex := 0;
  finally
    TreeBookmarks.Items.EndUpdate;
    CmbRecent.Items.EndUpdate;
  end;
end;

procedure TRADEPDFViewerForm.AddToRecentList(const AFileName: string);
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

procedure TRADEPDFViewerForm.BtnOpenPDFClick(Sender: TObject);
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

procedure TRADEPDFViewerForm.OpenPDFFile(const AFileName: string);
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
  LUserData := TPath.Combine(TPath.GetHomePath, 'RadeEssentials\PDFWebView2');
  ForceDirectories(LUserData);
  LBrowser.UserDataFolder := LUserData;
  LBrowser.Parent := LTab;
  LBrowser.Align := alClient;

  PageControlPDFs.ActivePage := LTab;
  SetStatus('Loading ' + ExtractFileName(LPath) + '...');
  UpdateWelcome;
end;

function TRADEPDFViewerForm.PdfFileUrl(const AFileName: string): string;
var
  LPath: string;
  LBytes: TBytes;
  LByte: Byte;
  LBuilder: TStringBuilder;
begin
  LPath := TPath.GetFullPath(AFileName).Replace('\', '/');
  LBytes := TEncoding.UTF8.GetBytes(LPath);
  if LPath.StartsWith('//') then
    LBuilder := TStringBuilder.Create('file:')
  else
    LBuilder := TStringBuilder.Create('file:///');
  try
    for LByte in LBytes do
      if ((LByte >= Ord('A')) and (LByte <= Ord('Z'))) or
        ((LByte >= Ord('a')) and (LByte <= Ord('z'))) or
        ((LByte >= Ord('0')) and (LByte <= Ord('9'))) or
        (LByte = Ord('-')) or (LByte = Ord('.')) or
        (LByte = Ord('_')) or (LByte = Ord('~')) or
        (LByte = Ord('/')) or (LByte = Ord(':')) then
        LBuilder.Append(Char(LByte))
      else
        LBuilder.Append('%').Append(IntToHex(LByte, 2));
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;

procedure TRADEPDFViewerForm.CmbRecentSelect(Sender: TObject);
begin
  if (CmbRecent.ItemIndex >= 0) and (CmbRecent.ItemIndex < FRecentFiles.Count) then
    OpenPDFFile(FRecentFiles[CmbRecent.ItemIndex]);
end;

procedure TRADEPDFViewerForm.RecentClick(Sender: TObject);
begin
  if (TreeBookmarks.Selected <> nil) and
    (TreeBookmarks.Selected.Data <> nil) then
    OpenPDFFile(FRecentFiles[NativeInt(TreeBookmarks.Selected.Data) - 1]);
end;

function TRADEPDFViewerForm.GetActiveBrowser: TEdgeBrowser;
begin
  Result := nil;
  if PageControlPDFs.ActivePage <> nil then
    Result := PageControlPDFs.ActivePage.FindComponent('PdfBrowser') as TEdgeBrowser;
end;

procedure TRADEPDFViewerForm.ActiveTabChanged(Sender: TObject);
begin
  if PageControlPDFs.ActivePage <> nil then
  begin
    Caption := 'PDF Studio - ' + PageControlPDFs.ActivePage.Caption;
    SetStatus(PageControlPDFs.ActivePage.Hint);
  end
  else
    Caption := 'PDF Studio';
  UpdateWelcome;
end;

procedure TRADEPDFViewerForm.BrowserCreateCompleted(Sender: TCustomEdgeBrowser;
  AResult: HResult);
var
  LTab: TTabSheet;
begin
  if AResult < 0 then
  begin
    SetStatus('WebView2 could not start. Install the Microsoft Edge WebView2 Runtime.');
    Exit;
  end;
  LTab := Sender.Owner as TTabSheet;
  if not Sender.Navigate(PdfFileUrl(LTab.Hint)) then
  begin
    if LTab = PageControlPDFs.ActivePage then
      SetStatus('Could not open ' + LTab.Caption + '.');
  end
  else if LTab = PageControlPDFs.ActivePage then
    SetStatus('Loading ' + LTab.Caption + '...');
end;

procedure TRADEPDFViewerForm.BrowserNavigationCompleted(Sender: TCustomEdgeBrowser;
  IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
begin
  if Sender.Owner = PageControlPDFs.ActivePage then
    if IsSuccess then
      SetStatus('Ready: ' + PageControlPDFs.ActivePage.Caption)
    else
      SetStatus(Format('PDF navigation failed (error %d).', [Ord(WebErrorStatus)]));
end;

procedure TRADEPDFViewerForm.UpdateWelcome;
begin
  PanelWelcome.Visible := PageControlPDFs.PageCount = 0;
  if PageControlPDFs.PageCount = 0 then
    SetStatus('Open a PDF to get started.');
end;

procedure TRADEPDFViewerForm.CloseActiveTab;
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

procedure TRADEPDFViewerForm.BtnMinimizeClick(Sender: TObject);
begin
  CloseActiveTab;
end;

procedure TRADEPDFViewerForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TRADEPDFViewerForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

procedure TRADEPDFViewerForm.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (ssCtrl in Shift) and (Key = Ord('O')) then
    BtnOpenPDFClick(Self)
  else if (ssCtrl in Shift) and (Key = Ord('W')) then
    CloseActiveTab
  else if (ssCtrl in Shift) and (Key = VK_ADD) then
    ZoomBy(0.1)
  else if (ssCtrl in Shift) and (Key = VK_SUBTRACT) then
    ZoomBy(-0.1)
  else
    Exit;
  Key := 0;
end;

procedure TRADEPDFViewerForm.ZoomBy(ADelta: Double);
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

procedure TRADEPDFViewerForm.ZoomOutClick(Sender: TObject);
begin
  ZoomBy(-0.1);
end;

procedure TRADEPDFViewerForm.ZoomInClick(Sender: TObject);
begin
  ZoomBy(0.1);
end;

procedure TRADEPDFViewerForm.SetStatus(const AText: string);
begin
  if LblStatus <> nil then
    LblStatus.Caption := AText;
end;

procedure TRADEPDFViewerForm.FormCreate(Sender: TObject);
begin
  FRecentFiles := TStringList.Create;
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  PageControlPDFs.OnChange := ActiveTabChanged;
  TreeBookmarks.OnDblClick := RecentClick;
  LblRecent.Caption := 'Recent';
  LblBookmarks.Caption := 'RECENT FILES';
  BtnOpenPDF.Caption := 'Open PDFs...';
  BtnMinimize.Caption := 'Close tab';
  BtnClose.Caption := 'Hide';
  PanelSidebar.BevelOuter := bvNone;
  PanelTopBar.BevelOuter := bvNone;
  TreeBookmarks.ReadOnly := True;
  TreeBookmarks.ShowHint := True;

  BtnZoomOut := TButton.Create(Self);
  BtnZoomOut.Parent := PanelTopBar;
  BtnZoomOut.SetBounds(455, 10, 36, 27);
  BtnZoomOut.Caption := '-';
  BtnZoomOut.Hint := 'Zoom out';
  BtnZoomOut.ShowHint := True;
  BtnZoomOut.OnClick := ZoomOutClick;

  BtnZoomIn := TButton.Create(Self);
  BtnZoomIn.Parent := PanelTopBar;
  BtnZoomIn.SetBounds(495, 10, 36, 27);
  BtnZoomIn.Caption := '+';
  BtnZoomIn.Hint := 'Zoom in';
  BtnZoomIn.ShowHint := True;
  BtnZoomIn.OnClick := ZoomInClick;

  PanelStatus := TPanel.Create(Self);
  PanelStatus.Parent := Self;
  PanelStatus.Align := alBottom;
  PanelStatus.Height := 26;
  PanelStatus.BevelOuter := bvNone;

  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := PanelStatus;
  LblStatus.Align := alClient;
  LblStatus.Layout := tlCenter;
  LblStatus.Caption := 'Open a PDF to get started.';

  PanelWelcome := TPanel.Create(Self);
  PanelWelcome.Parent := PageControlPDFs;
  PanelWelcome.Align := alClient;
  PanelWelcome.BevelOuter := bvNone;
  PanelWelcome.Padding.Top := 80;

  LblWelcome := TLabel.Create(Self);
  LblWelcome.Parent := PanelWelcome;
  LblWelcome.Align := alTop;
  LblWelcome.Height := 88;
  LblWelcome.Alignment := taCenter;
  LblWelcome.Layout := tlCenter;
  LblWelcome.Font.Size := 20;
  LblWelcome.Font.Style := [fsBold];
  LblWelcome.Caption := 'PDF Studio';

  BtnWelcomeOpen := TButton.Create(Self);
  BtnWelcomeOpen.Parent := PanelWelcome;
  BtnWelcomeOpen.Align := alTop;
  BtnWelcomeOpen.Height := 34;
  BtnWelcomeOpen.Margins.Left := 100;
  BtnWelcomeOpen.Margins.Right := 100;
  BtnWelcomeOpen.Margins.Top := 12;
  BtnWelcomeOpen.AlignWithMargins := True;
  BtnWelcomeOpen.Caption := 'Open PDF files';
  BtnWelcomeOpen.OnClick := BtnOpenPDFClick;

  LoadRecentList;
  UpdateWelcome;
end;

end.
