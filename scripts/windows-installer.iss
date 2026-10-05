#ifndef AppReleaseVersion
  #define AppReleaseVersion "1.0.1"
#endif

[Setup]
AppId={{7D0F066F-909A-4C06-B709-B57B5416CF0E}
AppName=泥土豆
AppVersion={#AppReleaseVersion}
AppPublisher=NeedTODO
DefaultDirName={autopf}\NeedTODO
DefaultGroupName=泥土豆
OutputDir=..\release
OutputBaseFilename=NeedTODO-Setup-{#AppReleaseVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=112,110
WizardBackColor=$F7F5F5
WizardImageBackColor=clWhite
WizardSmallImageBackColor=clWhite
DisableWelcomePage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\needtodo.exe

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked
[Files]
Source: "..\assets\potato.png"; Flags: dontcopy
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "portable.flag,user-data\*,使用说明.txt"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\泥土豆"; Filename: "{app}\needtodo.exe"
Name: "{autodesktop}\泥土豆"; Filename: "{app}\needtodo.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\needtodo.exe"; Description: "打开泥土豆"; Flags: nowait postinstall skipifsilent

[LangOptions]
DialogFontName=Microsoft YaHei UI
DialogFontSize=10
WelcomeFontName=Microsoft YaHei UI

[Messages]
ButtonBack=上一步
ButtonNext=下一步
ButtonInstall=安装
ButtonFinish=完成
ButtonCancel=取消
BrowseDialogTitle=选择安装文件夹
SelectDirDesc=选择安装位置
SelectDirLabel3=泥土豆将安装到以下文件夹。
SelectTasksDesc=快捷方式
SelectTasksLabel2=按需要选择快捷方式。
ReadyLabel1=已准备好安装泥土豆。
FinishedHeadingLabel=泥土豆已安装
FinishedLabel=清单、月历和日记，开始记录你的每一天。

[Code]
const
  AppPanel = $F7F5F5;
  AppInk = $322C29;
  AppMuted = $948B85;
  AppBlue = $AE7C47;
var
  Brand: TPngImage;
  NextSkin, BackSkin, CancelSkin: TBitmapButton;

procedure SkinClick(Sender: TObject);
begin
  if Sender = NextSkin then SendMessage(WizardForm.NextButton.Handle, $00F5, 0, 0)
  else if Sender = BackSkin then SendMessage(WizardForm.BackButton.Handle, $00F5, 0, 0)
  else SendMessage(WizardForm.CancelButton.Handle, $00F5, 0, 0);
end;

procedure PaintButton(Skin: TBitmapButton; Original: TNewButton; Primary: Boolean);
var
  Caption: String;
  TextX, TextY: Integer;
begin
  Skin.SetBounds(Original.Left - ScaleX(2), Original.Top - ScaleY(2), Original.Width + ScaleX(4), Original.Height + ScaleY(4));
  Skin.Visible := Original.Visible;
  Skin.Enabled := Original.Enabled;
  Skin.Bitmap.Width := Skin.Width;
  Skin.Bitmap.Height := Skin.Height;
  Skin.Bitmap.Canvas.Pen.Style := psClear;
  Skin.Bitmap.Canvas.Brush.Color := AppPanel;
  Skin.Bitmap.Canvas.Rectangle(0, 0, Skin.Width, Skin.Height);
  if Primary then Skin.Bitmap.Canvas.Brush.Color := AppBlue
  else Skin.Bitmap.Canvas.Brush.Color := $EFEAE5;
  Skin.Bitmap.Canvas.RoundRect(0, 0, Skin.Width, Skin.Height, ScaleX(14), ScaleY(14));
  Skin.Bitmap.Canvas.Font.Name := 'Microsoft YaHei UI';
  Skin.Bitmap.Canvas.Font.Size := 10;
  Skin.Bitmap.Canvas.Font.Style := [];
  if Primary then Skin.Bitmap.Canvas.Font.Color := clWhite
  else Skin.Bitmap.Canvas.Font.Color := AppBlue;
  if not Original.Enabled then Skin.Bitmap.Canvas.Font.Color := AppMuted;
  Caption := Original.Caption;
  StringChangeEx(Caption, '&', '', True);
  TextX := (Skin.Width - Skin.Bitmap.Canvas.TextWidth(Caption)) div 2;
  TextY := (Skin.Height - Skin.Bitmap.Canvas.TextHeight(Caption)) div 2;
  Skin.Bitmap.Canvas.TextOut(TextX, TextY, Caption);
  Skin.BringToFront;
  Skin.Invalidate;
end;

function MakeButton: TBitmapButton;
begin
  Result := TBitmapButton.Create(WizardForm);
  Result.Parent := WizardForm;
  Result.BackColor := AppPanel;
  Result.Cursor := crHandPoint;
  Result.TabStop := False;
  Result.OnClick := @SkinClick;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if NextSkin = nil then Exit;
  PaintButton(NextSkin, WizardForm.NextButton, True);
  PaintButton(BackSkin, WizardForm.BackButton, False);
  PaintButton(CancelSkin, WizardForm.CancelButton, False);
end;

procedure InitializeWizard;
var
  I: Integer;
begin
  WizardForm.Caption := '泥土豆 · 安装';
  WizardForm.Color := AppPanel;
  WizardForm.Font.Name := 'Microsoft YaHei UI';
  WizardForm.Font.Color := AppInk;
  WizardForm.Font.Size := 10;
  WizardForm.MainPanel.Color := clWhite;
  WizardForm.Bevel.Visible := False;
  WizardForm.Bevel1.Visible := False;
  for I := 0 to WizardForm.OuterNotebook.PageCount - 1 do
    WizardForm.OuterNotebook.Pages[I].Color := clWhite;
  for I := 0 to WizardForm.InnerNotebook.PageCount - 1 do
    WizardForm.InnerNotebook.Pages[I].Color := clWhite;
  WizardForm.PageNameLabel.Font.Style := [];
  WizardForm.PageNameLabel.StyleElements := WizardForm.PageNameLabel.StyleElements - [seFont];
  WizardForm.PageNameLabel.Font.Size := 14;
  WizardForm.PageNameLabel.Font.Color := AppInk;
  WizardForm.PageDescriptionLabel.Font.Color := AppMuted;
  WizardForm.PageDescriptionLabel.StyleElements := WizardForm.PageDescriptionLabel.StyleElements - [seFont];
  WizardForm.WelcomeLabel1.Caption := '泥土豆';
  WizardForm.WelcomeLabel1.Font.Style := [];
  WizardForm.WelcomeLabel1.StyleElements := WizardForm.WelcomeLabel1.StyleElements - [seFont];
  WizardForm.WelcomeLabel1.Font.Size := 24;
  WizardForm.WelcomeLabel1.Font.Color := AppInk;
  WizardForm.WelcomeLabel1.AdjustHeight;
  WizardForm.WelcomeLabel2.Top := WizardForm.WelcomeLabel1.Top + WizardForm.WelcomeLabel1.Height + ScaleY(20);
  WizardForm.WelcomeLabel2.Caption := '清单 · 桌面月历 · 日记' + #13#10 + #13#10 + '选择安装位置，开始记录你的每一天。';
  WizardForm.WelcomeLabel2.Font.Size := 11;
  WizardForm.WelcomeLabel2.StyleElements := WizardForm.WelcomeLabel2.StyleElements - [seFont];
  WizardForm.WelcomeLabel2.Font.Color := AppMuted;
  WizardForm.FinishedHeadingLabel.Font.Style := [];
  WizardForm.FinishedHeadingLabel.StyleElements := WizardForm.FinishedHeadingLabel.StyleElements - [seFont];
  WizardForm.FinishedHeadingLabel.Font.Size := 20;
  WizardForm.FinishedHeadingLabel.AdjustHeight;
  WizardForm.FinishedLabel.Top := WizardForm.FinishedHeadingLabel.Top + WizardForm.FinishedHeadingLabel.Height + ScaleY(16);
  WizardForm.FinishedLabel.Font.Color := AppMuted;
  WizardForm.FinishedLabel.StyleElements := WizardForm.FinishedLabel.StyleElements - [seFont];
  WizardForm.DirEdit.Color := AppPanel;
  WizardForm.TasksList.Color := clWhite;
  WizardForm.TasksList.BorderStyle := bsNone;
  WizardForm.RunList.Color := clWhite;
  WizardForm.RunList.BorderStyle := bsNone;
  WizardForm.ReadyMemo.Color := clWhite;
  WizardForm.ReadyMemo.BorderStyle := bsNone;
  WizardForm.ProgressGauge.Height := ScaleY(6);
  ExtractTemporaryFile('potato.png');
  Brand := TPngImage.Create;
  Brand.LoadFromFile(ExpandConstant('{tmp}\potato.png'));
  WizardForm.WizardBitmapImage.PngImage := Brand;
  WizardForm.WizardBitmapImage.BackColor := AppPanel;
  WizardForm.WizardBitmapImage.SetBounds(ScaleX(42), ScaleY(60), ScaleX(100), ScaleY(100));
  WizardForm.WizardBitmapImage.Stretch := True;
  WizardForm.WizardBitmapImage2.PngImage := Brand;
  WizardForm.WizardBitmapImage2.BackColor := AppPanel;
  WizardForm.WizardBitmapImage2.SetBounds(ScaleX(42), ScaleY(60), ScaleX(100), ScaleY(100));
  WizardForm.WizardBitmapImage2.Stretch := True;
  WizardForm.WizardSmallBitmapImage.PngImage := Brand;
  WizardForm.WizardSmallBitmapImage.BackColor := AppPanel;
  WizardForm.WizardSmallBitmapImage.Stretch := True;
  WizardForm.CancelButton.Width := ScaleX(84);
  WizardForm.CancelButton.Height := ScaleY(34);
  WizardForm.CancelButton.Left := WizardForm.ClientWidth - ScaleX(24) - WizardForm.CancelButton.Width;
  WizardForm.CancelButton.Top := WizardForm.ClientHeight - ScaleY(50);
  WizardForm.NextButton.Width := ScaleX(108);
  WizardForm.NextButton.Height := ScaleY(34);
  WizardForm.NextButton.Left := WizardForm.CancelButton.Left - ScaleX(12) - WizardForm.NextButton.Width;
  WizardForm.NextButton.Top := WizardForm.CancelButton.Top;
  WizardForm.BackButton.Width := ScaleX(84);
  WizardForm.BackButton.Height := ScaleY(34);
  WizardForm.BackButton.Left := WizardForm.NextButton.Left - ScaleX(12) - WizardForm.BackButton.Width;
  WizardForm.BackButton.Top := WizardForm.CancelButton.Top;
  NextSkin := MakeButton;
  BackSkin := MakeButton;
  CancelSkin := MakeButton;
end;
