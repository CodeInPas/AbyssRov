unit uGameController;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Math,
  uROVModel, uEnvironmentModel, uDatabaseManager, uSonarRenderer,
  uCameraRenderer, // <-- Impor Unit Kamera
  uAudioManager;

type
  TGameState = (gsStandby, gsActive, gsImploded, gsSignalLost, gsSuccess);

  TTelemetryUpdateEvent = procedure(Depth, Pressure, Hull, Power, Thrust: Single) of object;
  TSystemLogEvent = procedure(const LogMsg: String) of object;

  TGameController = class
  private
    FROVModel: TROVModel;
    FEnvModel: TEnvironmentModel;
    FDBManager: TDatabaseManager;
    FSonarRenderer: TSonarRenderer;
    FCameraRenderer: TCameraRenderer; // <-- Variabel Kamera

    FState: TGameState;
    FCurrentMissionID: Integer;
    FLastTick: QWord;
    FLastChunkDepth: Integer;

    FLastGlitchState: Boolean;

    FSonarPingTimer: Single;
    FAlarmTimer: Single;
    FRoarTimer: Single;

    FOnTelemetryUpdate: TTelemetryUpdateEvent;
    FOnSystemLog: TSystemLogEvent;

    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure CheckGameState;
    procedure UpdateEnvironment(Depth: Single);
  public
    constructor Create(ADBPath: String);
    destructor Destroy; override;

    procedure StartMission;
    procedure TerminateMission(ForcedSuccess: Boolean = False);
    procedure AttemptExtraction;

    procedure FireEMP;
    procedure DeployDecoy;

    property DBManager: TDatabaseManager read FDBManager;

    property ROVModel: TROVModel read FROVModel;
    property EnvModel: TEnvironmentModel read FEnvModel;
    property State: TGameState read FState;

    property SonarRenderer: TSonarRenderer read FSonarRenderer write FSonarRenderer;
    property CameraRenderer: TCameraRenderer read FCameraRenderer write FCameraRenderer; // <-- Properti Kamera

    property OnTelemetryUpdate: TTelemetryUpdateEvent read FOnTelemetryUpdate write FOnTelemetryUpdate;
    property OnSystemLog: TSystemLogEvent read FOnSystemLog write FOnSystemLog;
  end;

implementation

{ TGameController }

constructor TGameController.Create(ADBPath: String);
var
  Specs: TROVSpecs;
begin
  inherited Create;

  FDBManager := TDatabaseManager.Create(ADBPath);
  Specs := FDBManager.GetROVSpecs;

  FROVModel := TROVModel.Create(Specs.HullLevel, Specs.BatteryLevel, Specs.ThrusterLevel, Specs.DecoyLevel, Specs.EMPLevel);
  FEnvModel := TEnvironmentModel.Create(GetTickCount);

  FState := gsStandby;
  FLastTick := GetTickCount64;
  FLastChunkDepth := 0;
  FLastGlitchState := False;

  FSonarPingTimer := 0.0;
  FAlarmTimer := 0.0;
  FRoarTimer := 15.0;

  Application.OnIdle := @AppIdle;
end;

destructor TGameController.Destroy;
begin
  Application.OnIdle := nil;

  FDBManager.Free;
  FEnvModel.Free;
  FROVModel.Free;

  if Assigned(FSonarRenderer) then FSonarRenderer.Free;
  if Assigned(FCameraRenderer) then FCameraRenderer.Free; // <-- Pembersihan memori kamera

  inherited Destroy;
end;

procedure TGameController.StartMission;
var
  Specs: TROVSpecs;
begin
  if FState = gsActive then Exit;

  Specs := FDBManager.GetROVSpecs;

  FROVModel.Free;
  FROVModel := TROVModel.Create(Specs.HullLevel, Specs.BatteryLevel, Specs.ThrusterLevel, Specs.DecoyLevel, Specs.EMPLevel);

  FCurrentMissionID := FDBManager.StartNewMission;
  FState := gsActive;
  FLastTick := GetTickCount64;
  FLastChunkDepth := 0;
  FLastGlitchState := False;

  FSonarPingTimer := 0.0;
  FAlarmTimer := 0.0;
  FRoarTimer := 15.0;

  FEnvModel.GenerateChunk(0, 1000);

  if Assigned(AudioManager) then
    AudioManager.PlayAmbient(True);

  if Assigned(FOnSystemLog) then
    FOnSystemLog(Format('MISSION [%d] INITIATED. COMMENCING DESCENT.', [FCurrentMissionID]));
end;

procedure TGameController.TerminateMission(ForcedSuccess: Boolean = False);
var
  OutcomeStr: String;
begin
  if FState <> gsActive then Exit;

  if ForcedSuccess then
  begin
    FState := gsSuccess;
    OutcomeStr := 'SUCCESS';
  end
  else if FROVModel.HullIntegrity <= 0.0 then
  begin
    FState := gsImploded;
    OutcomeStr := 'IMPLOSION/DESTROYED';
  end
  else if FROVModel.Power <= 0.0 then
  begin
    FState := gsSignalLost;
    OutcomeStr := 'SIGNAL_LOST';
  end
  else
  begin
    FState := gsStandby;
    OutcomeStr := 'ABORTED';
  end;

  FDBManager.EndMission(FCurrentMissionID, FROVModel.Depth, OutcomeStr);

  if Assigned(AudioManager) then
  begin
    AudioManager.PlayAmbient(False);
    AudioManager.UpdateThrusterVolume(0.0);
  end;

  if Assigned(FOnSystemLog) then
    FOnSystemLog('MISSION TERMINATED: ' + OutcomeStr);
end;

procedure TGameController.AttemptExtraction;
var
  AnomList: TAnomalyList;
  i: Integer;
  Anom: TAnomaly;
  Extracted: Boolean;
  AnomTypeStr: String;
  RewardPts: Integer;
  ExtractionCmdValue: Single;
begin
  if FState <> gsActive then Exit;

  if FROVModel.IsExtracting then
  begin
    if Assigned(FOnSystemLog) then
      FOnSystemLog('EXTRACTION SYSTEM BUSY: ARM IS CURRENTLY DEPLOYED');
    Exit;
  end;

  AnomList := TAnomalyList.Create;
  try
    Extracted := False;
    ExtractionCmdValue := 0.0;

    if FEnvModel.GetAnomaliesInRadius(Trunc(FROVModel.X), Trunc(FROVModel.Y), 50, AnomList) > 0 then
    begin
      for i := 0 to AnomList.Count - 1 do
      begin
        Anom := AnomList[i];
        if not Anom.Secured then
        begin
          Anom.Secured := True;
          Extracted := True;
          RewardPts := 0;

          case Anom.AnomalyType of
            atBiomatter:
              begin
                AnomTypeStr := 'ORG_MATTER';
                RewardPts := 15;
              end;
            atRareOre:
              begin
                AnomTypeStr := 'RARE_ORE';
                RewardPts := 50;
              end;
            atUnknown:
              begin
                AnomTypeStr := 'UNKNOWN';
                RewardPts := 150;
              end;
            atBlackBox:
              begin
                AnomTypeStr := 'BLACK_BOX_DATA';
                RewardPts := 500;
                ExtractionCmdValue := 1.0;
              end;
          end;

          FDBManager.LogAnomaly(FCurrentMissionID, FROVModel.Depth, AnomTypeStr, FROVModel.HullIntegrity);
          FDBManager.AddResearchPointsAsync(RewardPts);

          if Assigned(AudioManager) then
            AudioManager.PlaySFX(sfxExtract);

          if Assigned(FOnSystemLog) then
          begin
            FOnSystemLog(Format('ANOMALY SECURED AT %.1fm: %s', [FROVModel.Depth, AnomTypeStr]));
            FOnSystemLog(Format('+%d RESEARCH POINTS ACQUIRED', [RewardPts]));

            if Anom.AnomalyType = atBlackBox then
              FOnSystemLog('WARNING: BLACK BOX DECRYPTION IN PROGRESS. ARM LOCKED FOR 10 SECONDS! NOISE LEVEL MAXIMUM!');
          end;

          Break;
        end;
      end;
    end;

    FROVModel.SendCommand(GetTickCount64, ctExtractSample, ExtractionCmdValue, 0, 0);

    if (not Extracted) and Assigned(FOnSystemLog) then
      FOnSystemLog('EXTRACTION FAILED: NO TARGET IN RANGE');
  finally
    AnomList.Free;
  end;
end;

procedure TGameController.FireEMP;
begin
  if FState <> gsActive then Exit;

  if FROVModel.EMPCooldownTimer > 0 then
  begin
    if Assigned(FOnSystemLog) then
      FOnSystemLog(Format('EMP RECHARGING. STANDBY: %.1f SEC', [FROVModel.EMPCooldownTimer]));
    Exit;
  end;

  FROVModel.SendCommand(GetTickCount64, ctFireEMP, 0, 0, 0);

  if Assigned(AudioManager) then
    AudioManager.PlaySFX(sfxEMP);

  if Assigned(FOnSystemLog) then
    FOnSystemLog('EMP DETONATED! SYSTEM ENTERING TEMPORARY BLACKOUT.');
end;

procedure TGameController.DeployDecoy;
begin
  if FState <> gsActive then Exit;

  if FROVModel.DecoyCooldownTimer > 0 then
  begin
    if Assigned(FOnSystemLog) then
      FOnSystemLog(Format('DECOY RELOADING. STANDBY: %.1f SEC', [FROVModel.DecoyCooldownTimer]));
    Exit;
  end;

  FROVModel.SendCommand(GetTickCount64, ctDeployDecoy, 0, 0, 0);

  if Assigned(AudioManager) then
    AudioManager.PlaySFX(sfxDecoy);

  if Assigned(FOnSystemLog) then
    FOnSystemLog('ACOUSTIC DECOY DEPLOYED. PREDATOR TRACKING DIVERTED.');
end;

procedure TGameController.UpdateEnvironment(Depth: Single);
var
  CurrentChunk: Integer;
begin
  CurrentChunk := Trunc(Depth) div 1000;
  if CurrentChunk > FLastChunkDepth then
  begin
    FLastChunkDepth := CurrentChunk;
    FEnvModel.GenerateChunk(FLastChunkDepth * 1000, (FLastChunkDepth + 1) * 1000);

    if Assigned(FOnSystemLog) then
      FOnSystemLog(Format('ENTERING NEW DEPTH SECTOR: %dm', [FLastChunkDepth * 1000]));
  end;
end;

procedure TGameController.CheckGameState;
begin
  if FState <> gsActive then Exit;

  if (FROVModel.HullIntegrity <= 0.0) or (FROVModel.Power <= 0.0) then
    TerminateMission(False);
end;

procedure TGameController.AppIdle(Sender: TObject; var Done: Boolean);
var
  CurrentTick: QWord;
  DeltaMS: UInt32;
  DeltaSec: Single;
begin
  Done := False;

  if FState <> gsActive then
  begin
    Sleep(10);
    Exit;
  end;

  CurrentTick := GetTickCount64;
  DeltaMS := CurrentTick - FLastTick;

  if DeltaMS >= 16 then
  begin
    FLastTick := CurrentTick;
    DeltaSec := DeltaMS / 1000.0;

    FEnvModel.UpdateEntities(DeltaSec, FROVModel.X, FROVModel.Y, FROVModel.IsNoisy);
    FROVModel.Update(DeltaMS, CurrentTick, FEnvModel);

    if FROVModel.IsGlitching <> FLastGlitchState then
    begin
      FLastGlitchState := FROVModel.IsGlitching;
      if FLastGlitchState then
      begin
        if Assigned(AudioManager) then AudioManager.PlaySFX(sfxGlitch);
        if Assigned(FOnSystemLog) then
          FOnSystemLog('W@RN!NG: C#IT1CAL M@GN3TIC INT3RFERENC3... 5YST3M M4LFUNCT1ON!');
      end
      else
      begin
        if Assigned(FOnSystemLog) then
          FOnSystemLog('SYSTEM RESTORED: MAGNETIC INTERFERENCE CLEARED.');
      end;
    end;

    if FROVModel.SonarActive and not FROVModel.IsBlackout then
    begin
      FSonarPingTimer := FSonarPingTimer - DeltaSec;
      if FSonarPingTimer <= 0 then
      begin
        if Assigned(AudioManager) then AudioManager.PlaySFX(sfxSonarPing);
        FSonarPingTimer := 3.6;
      end;
    end
    else
      FSonarPingTimer := 0.0;

    if (FROVModel.HullIntegrity < 30.0) or (FROVModel.Power < 15.0) then
    begin
      FAlarmTimer := FAlarmTimer - DeltaSec;
      if FAlarmTimer <= 0 then
      begin
        if Assigned(AudioManager) then AudioManager.PlaySFX(sfxAlarm);
        FAlarmTimer := 2.0;
      end;
    end
    else
      FAlarmTimer := 0.0;

    if FROVModel.Depth >= 1000.0 then
    begin
      FRoarTimer := FRoarTimer - DeltaSec;
      if FRoarTimer <= 0 then
      begin
        if Assigned(AudioManager) then AudioManager.PlaySFX(sfxLeviathanAggro);
        FRoarTimer := 20.0 + Random(40);
      end;
    end;

    UpdateEnvironment(FROVModel.Depth);
    CheckGameState;

    if Assigned(FOnTelemetryUpdate) then
      FOnTelemetryUpdate(FROVModel.Depth, FROVModel.GetAmbientPressure,
                         FROVModel.HullIntegrity, FROVModel.Power,
                         0.0);

    if Assigned(FSonarRenderer) then
      FSonarRenderer.RenderFrame(DeltaMS);

    // <-- Pemicu render untuk kamera
    if Assigned(FCameraRenderer) then
      FCameraRenderer.RenderFrame(DeltaMS);
  end;
end;

end.
