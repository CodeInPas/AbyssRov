unit uMainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, DBGrids, Db, sqldb, sqlite3conn, Math, LCLType, Menus,
  LCLIntf,

  bsbutton, bsprogress, uAnomaliesForm, TwLazUI.TrackBar, TwLazUI.ProgressBar,
  uGameController, uSonarRenderer, uCameraRenderer, // <-- TAMBAHAN: Import Unit Kamera
  uROVModel, uGarageForm, uAudioManager;

type

  { TMainForm }

  TMainForm = class(TForm)
    btnExtract: TBsButton;
    btnToggleSonar: TBsButton;
    btnDataLink: TBsButton;
    btnGarage: TBsButton;
    btnDeployDecoy: TBsButton;
    btnFireEMP: TBsButton;

    dsAnomalies: TDataSource;
    Label1: TLabel;
    lblControlTitle: TLabel;
    lblSonarRange: TLabel;
    lblSteering: TLabel;
    lblTerminalTitle: TLabel;
    lblThrust: TLabel;
    MainMenu1: TMainMenu;
    memoLog: TMemo;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    mnTutorID: TMenuItem;
    mnTutorEN: TMenuItem;
    mnTerminate: TMenuItem;
    mnTutorial: TMenuItem;
    MenuItem5: TMenuItem;
   // pbCamera: TPaintBox;
  //  pnlCameraFrame: TPanel;
    Panel2: TPanel;
    pnControl: TPanel;
    pbSonar: TPaintBox;

    // --- TAMBAHAN: Komponen Kamera LFM ---
    pnlCameraFrame: TPanel;
    pbCamera: TPaintBox;
    // -------------------------------------

    pnlControlBoard: TPanel;
    pnlTerminal: TPanel;
    tbSonarRange: TTwLazUITrackBar;
    tbSteering: TTwLazUITrackBar;
    tbThrust: TTwLazUITrackBar;
    UIConn: TSQLite3Connection;
    UIQuery: TSQLQuery;
    UITrans: TSQLTransaction;

    procedure btnDataLinkClick(Sender: TObject);
    procedure btnExtractClick(Sender: TObject);
    procedure mnTerminateClick(Sender: TObject);
    procedure mnTutorENClick(Sender: TObject);
    procedure mnTutorIDClick(Sender: TObject);
    procedure pbCameraClick(Sender: TObject);
    procedure tnDeployDecoyclick(Sender: TObject);
    procedure btnToggleSonarClick(Sender: TObject);
    procedure btnGarageClick(Sender: TObject);
    procedure btnDeployDecoyClick(Sender: TObject);
    procedure btnFireEMPClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure pbSonarPaint(Sender: TObject);
    procedure pbCameraPaint(Sender: TObject); // <-- TAMBAHAN
    procedure tbThrustChange(Sender: TObject);
    procedure tbSteeringChange(Sender: TObject);
  private
    FGameController: TGameController;
    FSonarActive: Boolean;

    procedure HandleTelemetryUpdate(Depth, Pressure, Hull, Power, Thrust: Single);
    procedure HandleSystemLog(const LogMsg: String);
    procedure RefreshUIQuery;

    procedure BtnMouseEnter(Sender: TObject);
    procedure BtnMouseLeave(Sender: TObject);
    procedure BindHoverEvents;

    procedure FormKeyDownDynamic(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUpDynamic(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
var
  DBPath: String;
begin
  BindHoverEvents;

  AudioManager := TAudioManager.Create;

  DBPath := ExtractFilePath(Application.ExeName) + 'data\abyss_log.db';
  ForceDirectories(ExtractFilePath(DBPath));

  FGameController := TGameController.Create(DBPath);
  FGameController.OnTelemetryUpdate := @HandleTelemetryUpdate;
  FGameController.OnSystemLog := @HandleSystemLog;

  // Inisialisasi Renderer Sonar
  FGameController.SonarRenderer := TSonarRenderer.Create(pbSonar, FGameController.EnvModel, FGameController.ROVModel);
  // Inisialisasi Renderer Kamera
  FGameController.CameraRenderer := TCameraRenderer.Create(pbCamera, FGameController.EnvModel, FGameController.ROVModel);

  FSonarActive := False;

  UIConn.DatabaseName := DBPath;
  UIQuery.SQL.Text := 'SELECT SampleID, DepthFound, AnomalyType, IntegrityAtExtraction FROM Extracted_Anomalies ORDER BY SampleID DESC';

  try
    UIConn.Connected := True;
    UIQuery.Open;
  except
  end;

  Self.KeyPreview := True;
  Self.OnKeyDown := @FormKeyDownDynamic;
  Self.OnKeyUp := @FormKeyUpDynamic;

  HandleSystemLog('SYSTEM INITIALIZED. STANDBY FOR MISSION DATA LINK.');
  HandleSystemLog('MANUAL OVERRIDE READY: USE [W][S] FOR THRUST, [A][D] FOR STEERING.');
  HandleSystemLog('COUNTERMEASURE HOTKEYS: [Q] DECOY | [E] EMP BURST');
end;

procedure TMainForm.BindHoverEvents;
begin
  if Assigned(btnDataLink) then
  begin
    btnDataLink.OnMouseEnter := @BtnMouseEnter;
    btnDataLink.OnMouseLeave := @BtnMouseLeave;
  end;

  if Assigned(btnExtract) then
  begin
    btnExtract.OnMouseEnter := @BtnMouseEnter;
    btnExtract.OnMouseLeave := @BtnMouseLeave;
  end;

  if Assigned(btnToggleSonar) then
  begin
    btnToggleSonar.OnMouseEnter := @BtnMouseEnter;
    btnToggleSonar.OnMouseLeave := @BtnMouseLeave;
  end;

  if Assigned(btnGarage) then
    begin
    btnGarage.OnMouseEnter := @BtnMouseEnter;
    btnGarage.OnMouseLeave := @BtnMouseLeave;
  end;

  if Assigned(btnDeployDecoy) then
  begin
    btnDeployDecoy.OnMouseEnter := @BtnMouseEnter;
    btnDeployDecoy.OnMouseLeave := @BtnMouseLeave;
  end;

  if Assigned(btnFireEMP) then
  begin
    btnFireEMP.OnMouseEnter := @BtnMouseEnter;
    btnFireEMP.OnMouseLeave := @BtnMouseLeave;
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  UIQuery.Close;
  UIConn.Connected := False;
  FGameController.Free;

  if Assigned(AudioManager) then
    AudioManager.Free;
end;

procedure TMainForm.BtnMouseEnter(Sender: TObject);
begin
  if (Sender is TPanel) and TPanel(Sender).Enabled then
  begin
    TPanel(Sender).Color := $003A2A1A;
    TPanel(Sender).Font.Color := clWhite;
  end;
end;

procedure TMainForm.BtnMouseLeave(Sender: TObject);
begin
  if (Sender is TPanel) and TPanel(Sender).Enabled then
  begin
    TPanel(Sender).Color := $00150F05;
    if Sender = btnGarage then
      TPanel(Sender).Font.Color := clYellow
    else if Sender = btnFireEMP then
      TPanel(Sender).Font.Color := clRed
    else
      TPanel(Sender).Font.Color := clAqua;
  end;
end;

procedure TMainForm.btnDataLinkClick(Sender: TObject);
begin
  if not Assigned(btnDataLink) or not btnDataLink.Enabled then Exit;

  if FGameController.State = gsActive then
  begin
    FGameController.TerminateMission(True);
    btnDataLink.Caption := 'DATA LINK [CONNECT]';
    btnDataLink.Font.Color := clAqua;
    tbThrust.Position := 50;
    if Assigned(tbSteering) then tbSteering.Position := 50;

    if Assigned(btnGarage) then
    begin
      btnGarage.Enabled := True;
      btnGarage.Font.Color := clYellow;
      btnGarage.Color := $00150F05;
    end;
    RefreshUIQuery;
  end
  else
  begin
    FGameController.StartMission;
    btnDataLink.Caption := 'DATA LINK [DISCONNECT]';
    btnDataLink.Font.Color := clRed;

    if Assigned(btnGarage) then
    begin
      btnGarage.Enabled := False;
      btnGarage.Font.Color := clGray;
      btnGarage.Color := clBlack;
    end;
    RefreshUIQuery;
  end;
end;

procedure TMainForm.btnExtractClick(Sender: TObject);
var
  AnomForm: TAnomaliesForm;
  DBPath: String;
begin
    DBPath := ExtractFilePath(Application.ExeName) + 'data\abyss_log.db';
    AnomForm := TAnomaliesForm.Create(Self);
    try
      AnomForm.SetDatabasePath(DBPath);
      AnomForm.RefreshData;
      AnomForm.ShowModal;
    finally
      AnomForm.Free;
    end;
end;

procedure TMainForm.mnTerminateClick(Sender: TObject);
begin
  Application.Terminate ;
end;

procedure TMainForm.mnTutorENClick(Sender: TObject);
begin
  OpenDocument(ExtractFilePath(Application.ExeName) + 'doc/Tutuorial_Abyss_Rov_ID.pdf');
end;

procedure TMainForm.mnTutorIDClick(Sender: TObject);
begin
  OpenDocument(ExtractFilePath(Application.ExeName) + 'doc/Tutuorial_Abyss_Rov_ID.pdf');
end;

procedure TMainForm.pbCameraClick(Sender: TObject);
begin

end;

procedure TMainForm.btnGarageClick(Sender: TObject);
var
  GarageForm: TGarageForm;
begin
  if not Assigned(btnGarage) or not btnGarage.Enabled then Exit;
  if FGameController.State = gsActive then
  begin
    ShowMessage('ACCESS DENIED: Cannot open Garage during an active mission.');
    Exit;
  end;

  GarageForm := TGarageForm.Create(Self);
  try
    GarageForm.SetDatabase(FGameController.DBManager);
    GarageForm.ShowModal;
  finally
    GarageForm.Free;
  end;
end;

procedure TMainForm.tnDeployDecoyclick(Sender: TObject);
begin
end;

procedure TMainForm.btnDeployDecoyClick(Sender: TObject);
begin
  if not Assigned(btnDeployDecoy) or not btnDeployDecoy.Enabled then Exit;
  if FGameController.State = gsActive then
    FGameController.DeployDecoy;
end;

procedure TMainForm.btnFireEMPClick(Sender: TObject);
begin
  if not Assigned(btnFireEMP) or not btnFireEMP.Enabled then Exit;
  if FGameController.State = gsActive then
    FGameController.FireEMP;
end;

procedure TMainForm.btnToggleSonarClick(Sender: TObject);
begin
  if not Assigned(btnToggleSonar) or not btnToggleSonar.Enabled then Exit;
  FSonarActive := not FSonarActive;
  if FSonarActive then
  begin
    btnToggleSonar.Caption := 'ACTIVE SONAR [ON]';
    btnToggleSonar.Font.Color := clLime;
  end
  else
  begin
    btnToggleSonar.Caption := 'ACTIVE SONAR [OFF]';
    btnToggleSonar.Font.Color := clAqua;
  end;

  if FGameController.State = gsActive then
    FGameController.ROVModel.SendCommand(GetTickCount64, ctToggleSonar, Ord(FSonarActive), 0, 800);
end;

procedure TMainForm.tbThrustChange(Sender: TObject);
var
  ThrustVal: Single;
begin
  lblThrust.Caption := Format('THRUSTER OUTPUT [%d%%]', [tbThrust.Position]);

  ThrustVal := Abs(tbThrust.Position - 50) * 2.0;
  if Assigned(AudioManager) then
    AudioManager.UpdateThrusterVolume(ThrustVal);

  if FGameController.State = gsActive then
    FGameController.ROVModel.SendCommand(GetTickCount64, ctSetThrust, (tbThrust.Position - 50) * 2, 0, 840);
end;

procedure TMainForm.tbSteeringChange(Sender: TObject);
begin
  if tbSteering.Position < 50 then
    lblSteering.Caption := Format('STEERING [PORT %d%%]', [(50 - tbSteering.Position) * 2])
  else if tbSteering.Position > 50 then
    lblSteering.Caption := Format('STEERING [STBD %d%%]', [(tbSteering.Position - 50) * 2])
  else
    lblSteering.Caption := 'STEERING [CENTER]';

  if FGameController.State = gsActive then
    FGameController.ROVModel.SendCommand(GetTickCount64, ctSetSteering, (tbSteering.Position - 50) * 2, 0, 150);
end;

procedure TMainForm.FormKeyDownDynamic(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FGameController.State <> gsActive then Exit;
  case Key of
    VK_A: if Assigned(tbSteering) then tbSteering.Position := Max(0, tbSteering.Position - 10);
    VK_D: if Assigned(tbSteering) then tbSteering.Position := Min(100, tbSteering.Position + 10);
    VK_W: if Assigned(tbThrust) then tbThrust.Position := Min(100, tbThrust.Position + 5);
    VK_S: if Assigned(tbThrust) then tbThrust.Position := Max(0, tbThrust.Position - 5);
    VK_Q: FGameController.DeployDecoy;
    VK_E: FGameController.FireEMP;
  end;
end;

procedure TMainForm.FormKeyUpDynamic(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FGameController.State <> gsActive then Exit;
  if (Key = VK_A) or (Key = VK_D) then
    if Assigned(tbSteering) then tbSteering.Position := 50;
end;

procedure TMainForm.pbSonarPaint(Sender: TObject);
begin
  if (FGameController <> nil) and (FGameController.SonarRenderer <> nil) then
    FGameController.SonarRenderer.RenderFrame(0);
end;

// --- TAMBAHAN BARU: Paint Handler untuk Kamera ---
procedure TMainForm.pbCameraPaint(Sender: TObject);
begin
  if (FGameController <> nil) and (FGameController.CameraRenderer <> nil) then
    FGameController.CameraRenderer.RenderFrame(0);
end;
// -------------------------------------------------

procedure TMainForm.HandleTelemetryUpdate(Depth, Pressure, Hull, Power, Thrust: Single);
var
  DescentThrustValue: Single;
begin
  DescentThrustValue := (tbThrust.Position - 50) * 0.1;

  if FGameController.State = gsActive then
  begin
     if Assigned(btnExtract) then
     begin
       if FGameController.ROVModel.IsExtracting then
       begin
         btnExtract.Caption := 'ARM ACTIVE [DEPLOYED]';
         btnExtract.Enabled := False;
         btnExtract.Font.Color := clGray;
         btnExtract.Color := clBlack;
       end
       else
       begin
         btnExtract.Caption := 'SAMPLING ARM [EXTRACT]';
         btnExtract.Enabled := True;
         btnExtract.Font.Color := clAqua;
         btnExtract.Color := $00150F05;
       end;
     end;

     if Assigned(btnDeployDecoy) then
     begin
       if FGameController.ROVModel.DecoyCooldownTimer > 0 then
       begin
         btnDeployDecoy.Caption := Format('DECOY CD: %.0fs', [FGameController.ROVModel.DecoyCooldownTimer]);
         btnDeployDecoy.Font.Color := clGray;
       end
       else
       begin
         btnDeployDecoy.Caption := 'DEPLOY DECOY [Q]';
         btnDeployDecoy.Font.Color := clAqua;
       end;
     end;

     if Assigned(btnFireEMP) then
     begin
       if FGameController.ROVModel.EMPCooldownTimer > 0 then
       begin
         btnFireEMP.Caption := Format('EMP CD: %.0fs', [FGameController.ROVModel.EMPCooldownTimer]);
         btnFireEMP.Font.Color := clGray;
       end
       else
       begin
         btnFireEMP.Caption := 'FIRE EMP [E]';
         btnFireEMP.Font.Color := clRed;
       end;
     end;

     if Abs(DescentThrustValue) > 0.1 then
       FGameController.ROVModel.Depth := Max(0.0, FGameController.ROVModel.Depth + DescentThrustValue);

     if Assigned(pbSonar) then
       pbSonar.Invalidate;

     // --- TAMBAHAN BARU: Pemicu Repaint Kamera ---
     if Assigned(pbCamera) then
       pbCamera.Invalidate;
     // --------------------------------------------
  end;
end;

procedure TMainForm.HandleSystemLog(const LogMsg: String);
var
  TimeStamp: String;
begin
  TimeStamp := FormatDateTime('hh:nn:ss', Now);
  memoLog.Lines.Add(TimeStamp + ' ' + LogMsg);
  memoLog.SelStart := Length(memoLog.Text);
end;

procedure TMainForm.RefreshUIQuery;
begin
  if UIQuery.Active then
  begin
    UIQuery.Close;
    UIQuery.Open;
  end;
end;

end.
