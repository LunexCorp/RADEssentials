unit RADE.Settings;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, System.IniFiles;

type
  TRADESettingsForm = class(TForm)
    LblShortcutFormatX: TLabel;
    EdtShortcutFormatX: TEdit;
    LblShortcutPDF: TLabel;
    EdtShortcutPDF: TEdit;
    BtnSave: TButton;
    BtnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
  private
    function GetIniPath: string;
    procedure LoadSettings;
    procedure SaveSettings;
  public
    class procedure ShowSettings;
  end;

implementation

{$R *.dfm}

class procedure TRADESettingsForm.ShowSettings;
var
  Form: TRADESettingsForm;
begin
  Form := TRADESettingsForm.Create(Application);
  try
    Form.ShowModal;
  finally
    Form.Free;
  end;
end;

function TRADESettingsForm.GetIniPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.GetHomePath) + 'RADEEssentials_Settings.ini';
end;

procedure TRADESettingsForm.FormCreate(Sender: TObject);
begin
  LoadSettings;
end;

procedure TRADESettingsForm.LoadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    EdtShortcutFormatX.Text := Ini.ReadString('Shortcuts', 'FormatX', 'Ctrl+Alt+F');
    EdtShortcutPDF.Text := Ini.ReadString('Shortcuts', 'PDFViewer', 'Ctrl+Alt+P');
  finally
    Ini.Free;
  end;
end;

procedure TRADESettingsForm.SaveSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    Ini.WriteString('Shortcuts', 'FormatX', EdtShortcutFormatX.Text);
    Ini.WriteString('Shortcuts', 'PDFViewer', EdtShortcutPDF.Text);
  finally
    Ini.Free;
  end;
end;

procedure TRADESettingsForm.BtnSaveClick(Sender: TObject);
begin
  SaveSettings;
  Close;
end;

end.
