unit uROVModel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections, uEnvironmentModel;

type
  { Enum untuk jenis instruksi jarak jauh ke ROV. }
  TROVCommandType = (ctSetThrust, ctSetSteering, ctToggleSonar, ctExtractSample, ctFireEMP, ctDeployDecoy);

  { Data struktur untuk antrean perintah dengan stempel waktu eksekusi }
  TROVCommand = record
    ExecuteTime: QWord;
    CommandType: TROVCommandType;
    Value1: Single;
    Value2: Single;
  end;

  TROVCommandQueue = specialize TQueue<TROVCommand>;

  TROVModel = class
  private
    FCommandQueue: TROVCommandQueue;

    // Status Fisik
    FX, FY: Single;
    FDepth: Single;
    FHullIntegrity: Single;
    FPower: Single;

    // Status Operasional
    FHeading: Single;
    FThrustTarget: Single;
    FCurrentThrust: Single;
    FSteeringTarget: Single;
    FCurrentSteering: Single;
    FSonarActive: Boolean;
    FExtractionPenaltyTimer: Single;

    // --- PSYCHOLOGICAL HORROR (GLITCH & ANOMALI) ---
    FIsGlitching: Boolean;
    FGlitchCooldown: Single;
    FGlitchDuration: Single;

    // --- ACTIVE COUNTERMEASURES ---
    FIsBlackout: Boolean;        // Status mati lampu total akibat efek samping EMP
    FBlackoutTimer: Single;
    FEMPCooldownTimer: Single;   // Cooldown senjata EMP
    FDecoyCooldownTimer: Single; // Cooldown pelepasan Decoy
    FDecoyLevel: Integer;
    FEMPLevel: Integer;

    // --- META-PROGRESSION MODIFIERS ---
    FYieldStrength: Single;       // Ambang batas tekanan sebelum lambung rusak
    FBatteryEfficiency: Single;   // Pengali penghematan daya (1.0 = standar, <1.0 = hemat)
    FThrustMultiplier: Single;    // Kecepatan maksimal pergerakan baling-baling

    // Konstanta Fisika Lingkungan & Spesifikasi Dasar
    const
      WATER_DENSITY_MULT = 0.0101;
      SURFACE_PRESSURE = 0.1;
      HULL_DECAY_RATE = 0.05;
      BASE_POWER_DRAIN = 0.1;
      THRUST_POWER_DRAIN = 0.5;
      STEERING_POWER_DRAIN = 0.2;
      SONAR_POWER_DRAIN = 0.8;
      ARM_POWER_BURST = 5.0;
      EMP_POWER_DRAIN = 15.0;        // Sedot daya besar saat menembakkan EMP
      WALL_DAMAGE_RATE = 15.0;       // Kerusakan lambung saat menabrak dinding karang per detik
      HOSTILE_DAMAGE_RATE = 75.0;    // Kerusakan lambung masif saat digigit/ditabrak monster

    procedure ProcessCommand(const Cmd: TROVCommand; EnvModel: TEnvironmentModel);
    function GetIsExtracting: Boolean;
    function GetIsNoisy: Boolean;
  public
    // Constructor menerima parameter level dari database saat instansiasi
    constructor Create(AHullLvl, ABatteryLvl, AThrusterLvl, ADecoyLvl, AEMPLvl: Integer);
    destructor Destroy; override;

    procedure SendCommand(CurrentTime: QWord; CmdType: TROVCommandType; Val1, Val2: Single; LatencyMS: UInt32);
    procedure Update(DeltaTimeMS: UInt32; CurrentTime: QWord; EnvModel: TEnvironmentModel);
    function GetAmbientPressure: Single;

    // Properti Public
    property X: Single read FX;
    property Y: Single read FY;
    property Depth: Single read FDepth write FDepth;
    property HullIntegrity: Single read FHullIntegrity;
    property Power: Single read FPower;
    property Heading: Single read FHeading;
    property SonarActive: Boolean read FSonarActive;
    property IsExtracting: Boolean read GetIsExtracting;

    property IsBlackout: Boolean read FIsBlackout;
    property EMPCooldownTimer: Single read FEMPCooldownTimer;
    property DecoyCooldownTimer: Single read FDecoyCooldownTimer;

    // Properti Stealth untuk mendeteksi apakah ROV memancing perhatian predator
    property IsNoisy: Boolean read GetIsNoisy;

    // Properti status Glitch (dapat dibaca oleh Renderer untuk efek visual)
    property IsGlitching: Boolean read FIsGlitching;
  end;

implementation

{ TROVModel }

constructor TROVModel.Create(AHullLvl, ABatteryLvl, AThrusterLvl, ADecoyLvl, AEMPLvl: Integer);
begin
  inherited Create;
  FCommandQueue := TROVCommandQueue.Create;
  FX := 0.0;
  FY := 0.0;
  FDepth := 0.0;
  FHullIntegrity := 100.0;
  FPower := 100.0;

  FHeading := 270.0;
  FThrustTarget := 0.0;
  FCurrentThrust := 0.0;
  FSteeringTarget := 0.0;
  FCurrentSteering := 0.0;
  FSonarActive := False;
  FExtractionPenaltyTimer := 0.0;

  // Inisialisasi status Glitch
  FIsGlitching := False;
  FGlitchCooldown := 15.0;
  FGlitchDuration := 0.0;

  // Inisialisasi status Countermeasures
  FDecoyLevel := ADecoyLvl;
  FEMPLevel := AEMPLvl;
  FIsBlackout := False;
  FBlackoutTimer := 0.0;
  FEMPCooldownTimer := 0.0;
  FDecoyCooldownTimer := 0.0;

  // --- TERAPKAN EFEK UPGRADE DARI GARASI ---
  // Level 1 = 60 MPa (~5900m). Setiap level menambah 20 MPa kedalaman aman.
  FYieldStrength := 60.0 + ((AHullLvl - 1) * 20.0);

  // Level 1 = 1.0 (100% konsumsi). Setiap level menghemat baterai 20%.
  FBatteryEfficiency := 1.0 - ((ABatteryLvl - 1) * 0.2);
  if FBatteryEfficiency < 0.2 then FBatteryEfficiency := 0.2; // Batas max efisiensi

  // Level 1 = 0.2x speed. Setiap level menambah output laju 0.08x.
  FThrustMultiplier := 0.2 + ((AThrusterLvl - 1) * 0.08);
end;

destructor TROVModel.Destroy;
begin
  FCommandQueue.Free;
  inherited Destroy;
end;

function TROVModel.GetIsExtracting: Boolean;
begin
  Result := FExtractionPenaltyTimer > 0;
end;

function TROVModel.GetIsNoisy: Boolean;
begin
  // ROV dianggap bising jika Sonar menyala, sedang mengebor (ekstraksi), atau mesin dipacu keras.
  // Selama 10 detik mengekstrak Black Box, FExtractionPenaltyTimer > 0, maka ini selalu True!
  // Jika sedang blackout, ROV sunyi senyap (kecuali diekstrak)
  Result := (not FIsBlackout) and (FSonarActive or GetIsExtracting or (Abs(FCurrentThrust) > 15.0));
end;

procedure TROVModel.SendCommand(CurrentTime: QWord; CmdType: TROVCommandType; Val1, Val2: Single; LatencyMS: UInt32);
var
  NewCmd: TROVCommand;
begin
  NewCmd.ExecuteTime := CurrentTime + LatencyMS;
  NewCmd.CommandType := CmdType;
  NewCmd.Value1 := Val1;
  NewCmd.Value2 := Val2;
  FCommandQueue.Enqueue(NewCmd);
end;

procedure TROVModel.ProcessCommand(const Cmd: TROVCommand; EnvModel: TEnvironmentModel);
var
  StunDur, Radius, DecoyDur: Single;
begin
  case Cmd.CommandType of
    ctSetThrust:
      FThrustTarget := EnsureRange(Cmd.Value1, -100.0, 100.0);

    ctSetSteering:
      FSteeringTarget := EnsureRange(Cmd.Value1, -100.0, 100.0);

    ctToggleSonar:
      if not FIsBlackout then FSonarActive := Cmd.Value1 > 0.5;

    ctExtractSample:
      begin
        // Jika Value1 > 0, maka ini adalah ekstraksi khusus (Black Box) yang memakan waktu 10 detik penuh
        if Cmd.Value1 > 0 then
          FExtractionPenaltyTimer := 10.0
        else
          FExtractionPenaltyTimer := 2.0; // Ekstraksi material normal

        FPower := Max(0.0, FPower - (ARM_POWER_BURST * FBatteryEfficiency));
      end;

    ctFireEMP:
      begin
        if (FEMPLevel > 0) and (FEMPCooldownTimer <= 0) and Assigned(EnvModel) then
        begin
          // Radius dan durasi stun bergantung pada level upgrade
          Radius := 300.0 + (FEMPLevel * 100.0);
          StunDur := 5.0 + (FEMPLevel * 2.0);

          EnvModel.TriggerEMP(FX, FY, Radius, StunDur);

          // Efek samping: Baterai terkuras instan & Blackout sistem
          FPower := Max(0.0, FPower - (EMP_POWER_DRAIN * FBatteryEfficiency));
          FIsBlackout := True;
          FBlackoutTimer := 3.0; // ROV mati lampu dan mati mesin 3 detik
          FSonarActive := False;
          FThrustTarget := 0.0;
          FSteeringTarget := 0.0;
          FCurrentThrust := 0.0;

          FEMPCooldownTimer := 30.0; // Cooldown senjata
        end;
      end;

    ctDeployDecoy:
      begin
        if (FDecoyLevel > 0) and (FDecoyCooldownTimer <= 0) and Assigned(EnvModel) then
        begin
          // Durasi decoy bergantung pada level upgrade
          DecoyDur := 5.0 + (FDecoyLevel * 2.5);
          // Lepaskan decoy tepat di belakang ROV (berlawanan dengan arah hadap)
          EnvModel.TriggerDecoy(
            FX - Cos(DegToRad(FHeading)) * 50,
            FY - Sin(DegToRad(FHeading)) * 50,
            DecoyDur
          );

          FDecoyCooldownTimer := 20.0; // Cooldown senjata
        end;
      end;
  end;
end;

function TROVModel.GetAmbientPressure: Single;
begin
  Result := SURFACE_PRESSURE + (FDepth * WATER_DENSITY_MULT);
end;

procedure TROVModel.Update(DeltaTimeMS: UInt32; CurrentTime: QWord; EnvModel: TEnvironmentModel);
var
  DeltaSec, Pressure, OverPressure, TotalDrain, ActiveSteeringTarget: Single;
  Cmd: TROVCommand;
  NextX, NextY: Single;
  CurrentDensity: Single;
begin
  if (FHullIntegrity <= 0.0) or (FPower <= 0.0) then Exit;

  DeltaSec := DeltaTimeMS / 1000.0;

  // Kurangi timer cooldown modul pertahanan
  if FEMPCooldownTimer > 0 then FEMPCooldownTimer := Max(0.0, FEMPCooldownTimer - DeltaSec);
  if FDecoyCooldownTimer > 0 then FDecoyCooldownTimer := Max(0.0, FDecoyCooldownTimer - DeltaSec);

  // Update status Blackout pasca-EMP
  if FIsBlackout then
  begin
    FBlackoutTimer := Max(0.0, FBlackoutTimer - DeltaSec);
    if FBlackoutTimer <= 0 then
      FIsBlackout := False; // Sistem kembali online
  end;

  // 1. Eksekusi Antrean Perintah
  while (FCommandQueue.Count > 0) and (FCommandQueue.Peek.ExecuteTime <= CurrentTime) do
  begin
    Cmd := FCommandQueue.Dequeue;
    ProcessCommand(Cmd, EnvModel);
  end;

  // 2. Update status Anomali Elektromagnetik (Psychological Horror)
  // Glitch hanya muncul pada kedalaman ekstrem ( >= 3000 meter )
  if FDepth >= 3000.0 then
  begin
    if FIsGlitching then
    begin
      FGlitchDuration := Max(0.0, FGlitchDuration - DeltaSec);
      if FGlitchDuration <= 0 then
      begin
        FIsGlitching := False; // Glitch selesai
        // Set cooldown sebelum glitch berikutnya (10 hingga 25 detik)
        FGlitchCooldown := 10.0 + (Random(150) / 10.0);
      end;
    end
    else
    begin
      FGlitchCooldown := Max(0.0, FGlitchCooldown - DeltaSec);
      if FGlitchCooldown <= 0 then
      begin
        FIsGlitching := True; // Glitch dimulai!
        // Berlangsung selama 3 hingga 7 detik
        FGlitchDuration := 3.0 + (Random(40) / 10.0);
      end;
    end;
  end
  else
  begin
    FIsGlitching := False;
    FGlitchCooldown := 15.0; // Reset waktu aman
  end;

  // 3. Timer Ekstraksi & Blackout (Keduanya melumpuhkan pergerakan)
  if (FExtractionPenaltyTimer > 0) or FIsBlackout then
  begin
    if FExtractionPenaltyTimer > 0 then
      FExtractionPenaltyTimer := Max(0.0, FExtractionPenaltyTimer - DeltaSec);

    // ROV kehilangan momentum secara drastis
    FCurrentThrust := FCurrentThrust * 0.9;
    FCurrentSteering := FCurrentSteering * 0.5;
  end
  else
  begin
    // 4. Akselerasi / Deselerasi Mesin Utama & Manuver
    ActiveSteeringTarget := FSteeringTarget;

    // EFEK HORROR: Jika Glitch aktif, arah kemudi dibalik secara paksa!
    if FIsGlitching then
      ActiveSteeringTarget := -ActiveSteeringTarget;

    if FCurrentThrust < FThrustTarget then
      FCurrentThrust := Min(FCurrentThrust + (25.0 * DeltaSec), FThrustTarget)
    else if FCurrentThrust > FThrustTarget then
      FCurrentThrust := Max(FCurrentThrust - (25.0 * DeltaSec), FThrustTarget);

    if FCurrentSteering < ActiveSteeringTarget then
      FCurrentSteering := Min(FCurrentSteering + (40.0 * DeltaSec), ActiveSteeringTarget)
    else if FCurrentSteering > ActiveSteeringTarget then
      FCurrentSteering := Max(FCurrentSteering - (40.0 * DeltaSec), ActiveSteeringTarget);
  end;

  // 5. Kalkulasi Rotasi
  if Abs(FCurrentSteering) > 0.1 then
  begin
    FHeading := FHeading + ((FCurrentSteering / 100.0) * 60.0 * DeltaSec);
    if FHeading >= 360.0 then FHeading := FHeading - 360.0;
    if FHeading < 0.0 then FHeading := FHeading + 360.0;
  end;

  // 6a. Kalkulasi Posisi Vektor 2D dengan Deteksi Benturan Topografi (Karang)
  if Abs(FCurrentThrust) > 0.1 then
  begin
    NextX := FX + (Cos(DegToRad(FHeading)) * (FCurrentThrust * FThrustMultiplier) * DeltaSec);
    NextY := FY + (Sin(DegToRad(FHeading)) * (FCurrentThrust * FThrustMultiplier) * DeltaSec);

    if Assigned(EnvModel) then
      CurrentDensity := EnvModel.GetDensity(Trunc(NextX), Trunc(NextY))
    else
      CurrentDensity := 0.0;

    if CurrentDensity > 0.8 then
    begin
      FX := FX - (Cos(DegToRad(FHeading)) * (FCurrentThrust * (FThrustMultiplier * 1.5)) * DeltaSec);
      FY := FY - (Sin(DegToRad(FHeading)) * (FCurrentThrust * (FThrustMultiplier * 1.5)) * DeltaSec);
      FThrustTarget := 0.0;
      FCurrentThrust := -FCurrentThrust * 0.5;
      FHullIntegrity := Max(0.0, FHullIntegrity - (WALL_DAMAGE_RATE * DeltaSec));
    end
    else
    begin
      FX := NextX;
      FY := NextY;
    end;
  end;

  // 6b. Deteksi Benturan dengan Entitas Biologis Bergerak (Hostile Leviathan)
  if Assigned(EnvModel) and EnvModel.CheckHostileCollision(FX, FY, 15.0) then
  begin
    FThrustTarget := 0.0;
    FCurrentThrust := -FCurrentThrust * 0.5;

    // QA BALANCE FIX: Armor Ekstraksi
    // Jika ROV sedang dalam proses ekstraksi (terutama ekstraksi Black Box yang butuh 10 detik),
    // aktifkan perlindungan sementara dari monster. Kerusakan diturunkan dari 75 ke 25 per detik.
    if FExtractionPenaltyTimer > 0 then
      FHullIntegrity := Max(0.0, FHullIntegrity - (25.0 * DeltaSec))
    else
      FHullIntegrity := Max(0.0, FHullIntegrity - (HOSTILE_DAMAGE_RATE * DeltaSec));
  end;

  // 7. Kalkulasi Tekanan (Pressure) & Kerusakan Lambung berdasar Upgrade Hull
  Pressure := GetAmbientPressure;
  if Pressure > FYieldStrength then
  begin
    OverPressure := Pressure - FYieldStrength;
    FHullIntegrity := Max(0.0, FHullIntegrity - (OverPressure * HULL_DECAY_RATE * DeltaSec));
  end;

  // 8. Kalkulasi Drainase Baterai berdasar Upgrade Battery
  TotalDrain := BASE_POWER_DRAIN;
  TotalDrain := TotalDrain + ((Abs(FCurrentThrust) / 100.0) * THRUST_POWER_DRAIN);
  TotalDrain := TotalDrain + ((Abs(FCurrentSteering) / 100.0) * STEERING_POWER_DRAIN);

  if FSonarActive and not FIsBlackout then
    TotalDrain := TotalDrain + SONAR_POWER_DRAIN;

  TotalDrain := TotalDrain * FBatteryEfficiency;
  FPower := Max(0.0, FPower - (TotalDrain * DeltaSec));
end;

end.
