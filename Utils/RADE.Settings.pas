unit RADE.Settings;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Menus,
  System.IniFiles;

type
  TRADESettingsForm = class(TForm)
    LblShortcutFormatX: TLabel;
    EdtShortcutFormatX: TEdit;
    LblShortcutPDF: TLabel;
    EdtShortcutPDF: TEdit;
    LblShortcutInstructions: TLabel;
    BtnSave: TButton;
    BtnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
  private
    procedure ShortcutEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ShortcutEditKeyPress(Sender: TObject; var Key: Char);
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
  EdtShortcutFormatX.ReadOnly := True;
  EdtShortcutPDF.ReadOnly := True;
  EdtShortcutFormatX.OnKeyDown := ShortcutEditKeyDown;
  EdtShortcutPDF.OnKeyDown := ShortcutEditKeyDown;
  EdtShortcutFormatX.OnKeyPress := ShortcutEditKeyPress;
  EdtShortcutPDF.OnKeyPress := ShortcutEditKeyPress;
  EdtShortcutFormatX.Hint := 'Click here, then press the shortcut keys.';
  EdtShortcutPDF.Hint := 'Click here, then press the shortcut keys.';
  EdtShortcutFormatX.ShowHint := True;
  EdtShortcutPDF.ShowHint := True;
  LoadSettings;
end;

procedure TRADESettingsForm.ShortcutEditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
  begin
    Key := 0;
    Exit;
  end;

  if Sender is TEdit then
    TEdit(Sender).Text := ShortCutToText(ShortCut(Key, Shift));
  Key := 0;
end;

procedure TRADESettingsForm.ShortcutEditKeyPress(Sender: TObject; var Key: Char);
begin
  Key := #0;
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
