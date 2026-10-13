unit uSonarRenderer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ExtCtrls, Math,
  BGRABitmap, BGRABitmapTypes, uEnvironmentModel, uROVModel;

type
  TSonarRenderer = class
  private
    FTargetBox: TPaintBox;
    FEnvModel: TEnvironmentModel;
    FROVModel: TROVModel;

    FMainBuffer: TBGRABitmap;
    FStaticTerrain: TBGRABitmap;

    FSweepAngle: Single;
    FLastROVX, FLastROVY: Integer;
    FTerrainNeedsUpdate: Boolean;

    const
      UPDATE_THRESHOLD = 20;
      RENDER_STEP = 2; // Lebih kecil = Lebih padat dan halus
      RADAR_RADIUS = 350;

    procedure UpdateStaticTerrain;
    procedure DrawCoordinateGrid;
    procedure DrawRadarConcentric;
    procedure DrawSweepTrail(DeltaSec: Single);
    procedure DrawAnomalies;
    procedure DrawHostiles; // Monster asli
    procedure DrawDecoy;    // Titik lokasi Decoy
    procedure DrawGlitchEffects; // Efek visual anomali magnetik
    procedure DrawScanlines;     // Efek scanline CRT
    procedure DrawHUDOverlay;
    procedure DrawTelemetryOverlay; // <-- Tambahan baru
    procedure DrawDamageVignette;
  public
    constructor Create(APaintBox: TPaintBox; AEnv: TEnvironmentModel; AROV: TROVModel);
    destructor Destroy; override;
    procedure RenderFrame(DeltaTimeMS: UInt32);
  end;

implementation

{ TSonarRenderer }

constructor TSonarRenderer.Create(APaintBox: TPaintBox; AEnv: TEnvironmentModel; AROV: TROVModel);
begin
  inherited Create;
  FTargetBox := APaintBox;
  FEnvModel := AEnv;
  FROVModel := AROV;

  FMainBuffer := TBGRABitmap.Create(FTargetBox.Width, FTargetBox.Height, BGRA(0,0,0,255));
  FStaticTerrain := TBGRABitmap.Create(FTargetBox.Width, FTargetBox.Height, BGRA(0,0,0,255));

  FSweepAngle := 0.0;
  FLastROVX := -9999;
  FLastROVY := -9999;
  FTerrainNeedsUpdate := True;
end;

destructor TSonarRenderer.Destroy;
begin
  FMainBuffer.Free;
  FStaticTerrain.Free;
  inherited Destroy;
end;

procedure TSonarRenderer.UpdateStaticTerrain;
var
  x, y, WorldX, WorldY: Integer;
  Density: Single;
  Col: TBGRAPixel;
  W, H: Integer;
begin
  W := FStaticTerrain.Width;
  H := FStaticTerrain.Height;

  // Base background: Deep Navy Blue (warna palung laut)
  FStaticTerrain.Fill(BGRA(5, 15, 35, 255));

  y := 0;
  while y < H do
  begin
    x := 0;
    while x < W do
    begin
      WorldX := Trunc(FROVModel.X) + (x - (W div 2));
      WorldY := Trunc(FROVModel.Y) + (y - (H div 2));
      Density := FEnvModel.GetDensity(WorldX, WorldY);

      if Density > 0.3 then
      begin
        // Transisi Warna Mulus (Smooth Gradient)
        if Density < 0.5 then
          Col := BGRA(10, Trunc(40 + (Density * 100)), Trunc(60 + (Density * 80)), 255) // Teal Gelap
        else if Density < 0.7 then
          Col := BGRA(15, Trunc(100 + (Density * 80)), 40, 255) // Hijau Lumut
        else
          Col := BGRA(40, Trunc(150 + (Density * 50)), 20, 255); // Hijau Kekuningan (Dangkal/Tinggi)

        // Garis Kontur Topografi Tipis (Topographic Contour Lines)
        if (Abs(Density - 0.45) < 0.008) or
           (Abs(Density - 0.60) < 0.008) or
           (Abs(Density - 0.75) < 0.008) then
        begin
          Col := BGRA(0, 255, 150, 180); // Neon Cyan/Green untuk garis kontur
        end;

        FStaticTerrain.FillRect(x, y, x + RENDER_STEP, y + RENDER_STEP, Col, dmSet);
      end;
      Inc(x, RENDER_STEP);
    end;
    Inc(y, RENDER_STEP);
  end;

  FLastROVX := Trunc(FROVModel.X);
  FLastROVY := Trunc(FROVModel.Y);
  FTerrainNeedsUpdate := False;
end;

procedure TSonarRenderer.DrawCoordinateGrid;
var
  i, x, y: Integer;
begin
  // Grid Kotak-kotak latar belakang (Faint Square Grid)
  for i := 0 to (FMainBuffer.Width div 50) do
  begin
    x := i * 50;
    FMainBuffer.DrawLineAntialias(x, 0, x, FMainBuffer.Height, BGRA(0, 150, 150, 25), 1.0);
  end;

  for i := 0 to (FMainBuffer.Height div 50) do
  begin
    y := i * 50;
    FMainBuffer.DrawLineAntialias(0, y, FMainBuffer.Width, y, BGRA(0, 150, 150, 25), 1.0);
  end;
end;

procedure TSonarRenderer.DrawRadarConcentric;
var
  CX, CY, i: Integer;
  RadH: Single;
  P1, P2, P3: TPointF;
begin
  CX := FMainBuffer.Width div 2;
  CY := FMainBuffer.Height div 2;

  // Crosshair
  FMainBuffer.DrawLineAntialias(CX, CY - RADAR_RADIUS - 20, CX, CY + RADAR_RADIUS + 20, BGRA(0, 255, 200, 60), 1.0);
  FMainBuffer.DrawLineAntialias(CX - RADAR_RADIUS - 20, CY, CX + RADAR_RADIUS + 20, CY, BGRA(0, 255, 200, 60), 1.0);

  // Lingkaran Konsentris Radar Dalam
  for i := 1 to 3 do
    FMainBuffer.EllipseAntialias(CX, CY, (RADAR_RADIUS div 4) * i, (RADAR_RADIUS div 4) * i, BGRA(0, 255, 150, 50), 1.0);

  // Lingkaran Batas Luar (Neon Ring yang terang)
  FMainBuffer.EllipseAntialias(CX, CY, RADAR_RADIUS, RADAR_RADIUS, BGRA(0, 255, 180, 200), 3.0);
  FMainBuffer.EllipseAntialias(CX, CY, RADAR_RADIUS, RADAR_RADIUS, BGRA(0, 255, 180, 80), 6.0); // Outer Glow

  if FROVModel.IsExtracting then
    FMainBuffer.EllipseAntialias(CX, CY, 50, 50, BGRA(255, 100, 0, 200), 2.0);

  // --- PERBAIKAN: Ikon ROV Segitiga Kuning Dibalik Arahnya ---
  // Kita balikkan polaritas (minus menjadi plus, dan sebaliknya) pada RadH
  //RadH := DegToRad(FROVModel.Heading + 180); // Putar 180 Derajat
  RadH := DegToRad(FROVModel.Heading ); // Putar 0 Derajat

  // Titik Ujung Depan (P1)
  P1.x := CX + (16 * Cos(RadH));
  P1.y := CY + (16 * Sin(RadH));

  // Titik Kiri Belakang (P2)
  P2.x := CX + (-10 * Cos(RadH) + 10 * Sin(RadH));
  P2.y := CY + (-10 * Sin(RadH) - 10 * Cos(RadH));

  // Titik Kanan Belakang (P3)
  P3.x := CX + (-10 * Cos(RadH) - 10 * Sin(RadH));
  P3.y := CY + (-10 * Sin(RadH) + 10 * Cos(RadH));

  // --- PERBAIKAN WARNA: Glow Ikon ROV Menjadi Kuning Terang ---
  FMainBuffer.DrawPolygonAntialias([P1, P2, P3], BGRA(255, 255, 0, 255), 2.0); // Garis kuning padat
  FMainBuffer.DrawPolygonAntialias([P1, P2, P3], BGRA(255, 200, 0, 100), 5.0); // Glow luar kuning
end;

procedure TSonarRenderer.DrawSweepTrail(DeltaSec: Single);
var
  CX, CY, i: Integer;
  EndX, EndY: Single;
  RadAngle: Single;
  TrailAlpha: Byte;
begin
  if FROVModel.SonarActive then
  begin
    // Jika glitch aktif, sapuan sonar bergerak acak dan tersendat
    if FROVModel.IsGlitching then
      FSweepAngle := FSweepAngle + (Random(300) * DeltaSec)
    else
      FSweepAngle := FSweepAngle + (100.0 * DeltaSec);
  end;

  if FSweepAngle >= 360.0 then FSweepAngle := FSweepAngle - 360.0;

  CX := FMainBuffer.Width div 2;
  CY := FMainBuffer.Height div 2;

  // Efek Ekor Sapuan (Sweep Trail)
  for i := 0 to 40 do
  begin
    RadAngle := DegToRad(FSweepAngle - i);
    EndX := CX + Cos(RadAngle) * RADAR_RADIUS;
    EndY := CY + Sin(RadAngle) * RADAR_RADIUS;

    TrailAlpha := Trunc(120 * (1.0 - (i / 40.0)));
    FMainBuffer.DrawLineAntialias(CX, CY, EndX, EndY, BGRA(0, 255, 150, TrailAlpha), 2.0);
  end;

  // Garis Utama Sonar
  RadAngle := DegToRad(FSweepAngle);
  EndX := CX + Cos(RadAngle) * RADAR_RADIUS;
  EndY := CY + Sin(RadAngle) * RADAR_RADIUS;

  if FROVModel.IsGlitching and (Random(10) > 5) then
    FMainBuffer.DrawLineAntialias(CX, CY, EndX, EndY, BGRA(255, 50, 50, 255), 3.0) // Red flicker
  else
    FMainBuffer.DrawLineAntialias(CX, CY, EndX, EndY, BGRA(150, 255, 255, 255), 3.0);
end;

procedure TSonarRenderer.DrawAnomalies;
var
  AnomList: TAnomalyList;
  i: Integer;
  Anom: TAnomaly;
  ScreenX, ScreenY: Integer;
  CX, CY: Integer;
  BlipColor: TBGRAPixel;
  BoxPts: array[0..3] of TPointF;
begin
  AnomList := TAnomalyList.Create;
  try
    CX := FMainBuffer.Width div 2;
    CY := FMainBuffer.Height div 2;

    FEnvModel.GetAnomaliesInRadius(Trunc(FROVModel.X), Trunc(FROVModel.Y), RADAR_RADIUS, AnomList);

    for i := 0 to AnomList.Count - 1 do
    begin
      Anom := AnomList[i];
      ScreenX := CX + (Anom.X - Trunc(FROVModel.X));
      ScreenY := CY + (Anom.Y - Trunc(FROVModel.Y));

      case Anom.AnomalyType of
        atBiomatter: BlipColor := BGRA(0, 255, 100, 255);
        atRareOre: BlipColor := BGRA(255, 200, 0, 255);
        atUnknown: BlipColor := BGRA(255, 50, 50, 255);
        atBlackBox: BlipColor := BGRA(200, 50, 255, 255); // Ungu untuk Black Box
      end;

      if Anom.AnomalyType = atBlackBox then
      begin
        // Ikon Kotak Putih/Ungu khusus untuk Black Box
        FMainBuffer.FillRect(ScreenX - 3, ScreenY - 3, ScreenX + 3, ScreenY + 3, BGRA(255, 255, 255, 255), dmSet);

        // Setup kotak pertama (inner aura)
        BoxPts[0] := PointF(ScreenX - 8, ScreenY - 8);
        BoxPts[1] := PointF(ScreenX + 8, ScreenY - 8);
        BoxPts[2] := PointF(ScreenX + 8, ScreenY + 8);
        BoxPts[3] := PointF(ScreenX - 8, ScreenY + 8);

        BlipColor.alpha := 180;
        FMainBuffer.DrawPolygonAntialias(BoxPts, BlipColor, 2.0);

        // Setup kotak kedua (outer aura)
        BoxPts[0] := PointF(ScreenX - 15, ScreenY - 15);
        BoxPts[1] := PointF(ScreenX + 15, ScreenY - 15);
        BoxPts[2] := PointF(ScreenX + 15, ScreenY + 15);
        BoxPts[3] := PointF(ScreenX - 15, ScreenY + 15);

        BlipColor.alpha := 60;
        FMainBuffer.DrawPolygonAntialias(BoxPts, BlipColor, 1.0);
      end
      else
      begin
        // Triple-layer Glow Effect untuk Blips anomali normal
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 3, 3, BlipColor, 1.0, BlipColor);

        BlipColor.alpha := 120;
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 8, 8, BlipColor, 1.0, BlipColor);

        BlipColor.alpha := 40;
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 18, 18, BlipColor, 1.0, BlipColor);
      end;
    end;
  finally
    AnomList.Free;
  end;
end;

procedure TSonarRenderer.DrawDecoy;
var
  ScreenX, ScreenY: Integer;
  CX, CY: Integer;
  BlipColor: TBGRAPixel;
begin
  if not FEnvModel.IsDecoyActive then Exit;

  CX := FMainBuffer.Width div 2;
  CY := FMainBuffer.Height div 2;

  // Hitung posisi decoy di layar radar
  ScreenX := CX + (Trunc(FEnvModel.DecoyX) - Trunc(FROVModel.X));
  ScreenY := CY + (Trunc(FEnvModel.DecoyY) - Trunc(FROVModel.Y));

  // Pastikan decoy masih di dalam radius radar
  if Sqr(ScreenX - CX) + Sqr(ScreenY - CY) <= Sqr(RADAR_RADIUS) then
  begin
    BlipColor := BGRA(255, 255, 0, 255); // Kuning terang untuk Decoy

    FMainBuffer.FontHeight := 14;
    FMainBuffer.FontName := 'Consolas';
    FMainBuffer.FontAntialias := True;

    // Kedipan (Pulse) radius luar
    if (GetTickCount64 mod 500) > 250 then
    begin
      FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 8, 8, BlipColor, 2.0);
      BlipColor.alpha := 80;
      FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 30, 30, BlipColor, 2.0);
    end;

    // Inti Decoy
    BlipColor.alpha := 255;
    FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 4, 4, BlipColor, 1.0, BlipColor);

    FMainBuffer.TextOut(ScreenX + 10, ScreenY + 10, 'DECOY ACTIVE', BGRA(255, 255, 0, 200));
  end;
end;

procedure TSonarRenderer.DrawHostiles;
var
  HostileList: THostileList;
  i: Integer;
  H: THostileEntity;
  ScreenX, ScreenY: Integer;
  CX, CY: Integer;
  BlipColor: TBGRAPixel;
begin
  HostileList := THostileList.Create;
  try
    CX := FMainBuffer.Width div 2;
    CY := FMainBuffer.Height div 2;

    FEnvModel.GetHostilesInRadius(Trunc(FROVModel.X), Trunc(FROVModel.Y), RADAR_RADIUS, HostileList);

    FMainBuffer.FontHeight := 14;
    FMainBuffer.FontName := 'Consolas';
    FMainBuffer.FontAntialias := True;

    for i := 0 to HostileList.Count - 1 do
    begin
      H := HostileList[i];
      ScreenX := CX + (Trunc(H.X) - Trunc(FROVModel.X));
      ScreenY := CY + (Trunc(H.Y) - Trunc(FROVModel.Y));

      if H.StunTimer > 0 then
      begin
        // Monster kena EMP Stun - Biru pucat dan tidak bergerak
        BlipColor := BGRA(100, 200, 255, 150);
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 5, 5, BlipColor, 1.0, BlipColor);
        FMainBuffer.TextOut(ScreenX + 10, ScreenY - 10, 'STUNNED', BlipColor);
      end
      else if H.IsHunting then
      begin
        // Monster Hunting - Merah Agresif
        BlipColor := BGRA(255, 20, 20, 255);
        FMainBuffer.DrawLineAntialias(ScreenX, ScreenY, CX, CY, BGRA(255, 0, 0, 150), 2.0);
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 6, 6, BlipColor, 1.0, BlipColor);

        BlipColor.alpha := 150;
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 15, 15, BlipColor, 2.0);
        BlipColor.alpha := 80;
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 25, 25, BlipColor, 1.0);

        FMainBuffer.TextOut(ScreenX + 15, ScreenY - 10, 'WARNING: TRACKING', BGRA(255, 50, 50, 255));
      end
      else
      begin
        // Monster Patroli - Merah Gelap
        BlipColor := BGRA(150, 0, 0, 200);
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 4, 4, BlipColor, 1.0, BlipColor);
        BlipColor.alpha := 50;
        FMainBuffer.EllipseAntialias(ScreenX, ScreenY, 12, 12, BlipColor, 1.0, BlipColor);
      end;
    end;
  finally
    HostileList.Free;
  end;
end;

procedure TSonarRenderer.DrawGlitchEffects;
var
  i, rx, ry, CX, CY: Integer;
  BlipColor: TBGRAPixel;
  BlockHeight: Integer;
begin
  if not FROVModel.IsGlitching then Exit;

  CX := FMainBuffer.Width div 2;
  CY := FMainBuffer.Height div 2;

  // 1. VHS Static Scanlines
  for i := 0 to 80 do
  begin
    rx := Random(FMainBuffer.Width);
    ry := Random(FMainBuffer.Height);
    FMainBuffer.DrawLineAntialias(rx, ry, rx + Random(200), ry, BGRA(255, 255, 255, Random(100)), 1.5);
  end;

  // 2. Glitch Blocks (Distorsi sinyal digital patah-patah)
  for i := 0 to 5 do
  begin
    rx := Random(FMainBuffer.Width);
    ry := Random(FMainBuffer.Height);
    BlockHeight := Random(20) + 5;
    FMainBuffer.FillRect(0, ry, FMainBuffer.Width, ry + BlockHeight, BGRA(0, 255, 0, 30), dmDrawWithTransparency);
  end;

  // 3. Phantom Blips (Halusinasi Target)
  for i := 0 to 2 do
  begin
    // Posisi acak di sekitar radar
    rx := CX + (Random(RADAR_RADIUS * 2) - RADAR_RADIUS);
    ry := CY + (Random(RADAR_RADIUS * 2) - RADAR_RADIUS);

    BlipColor := BGRA(255, Random(50), Random(50), 255);

    // Tarik garis merah menipu ke tengah (seolah memburu pemain)
    if Random(10) > 4 then
      FMainBuffer.DrawLineAntialias(rx, ry, CX, CY, BGRA(255, 0, 0, 100), 1.5);

    FMainBuffer.EllipseAntialias(rx, ry, 6, 6, BlipColor, 1.0, BlipColor);

    BlipColor.alpha := 150;
    FMainBuffer.EllipseAntialias(rx, ry, Random(20)+10, Random(20)+10, BlipColor, 2.0);

    if Random(10) > 5 then
      FMainBuffer.TextOut(rx + 15, ry - 10, 'W@RN!NG: ???', BGRA(255, 50, 50, 255));
  end;
end;

procedure TSonarRenderer.DrawScanlines;
var
  y: Integer;
begin
  // Efek garis-garis pemindai CRT klasik
  // Menggambar garis gelap transparan berselang-seling dari atas ke bawah
  y := 0;
  while y < FMainBuffer.Height do
  begin
    FMainBuffer.DrawLineAntialias(0, y, FMainBuffer.Width, y, BGRA(0, 0, 0, 40), 1.0);
    Inc(y, 3); // Jarak antar scanline
  end;
end;

procedure TSonarRenderer.DrawHUDOverlay;
var
  Txt: String;
  HUDColor: TBGRAPixel;
begin
  FMainBuffer.FontHeight := 16;
  FMainBuffer.FontName := 'Consolas';
  FMainBuffer.FontAntialias := True;

  // Jika Blackout aktif akibat EMP, HUD tetap digambar (meskipun layarnya mati)
  FMainBuffer.FillRect(10, 10, 300, 70, BGRA(0, 0, 0, 180), dmDrawWithTransparency);

  if FROVModel.IsGlitching then
  begin
    FMainBuffer.TextOut(20, 20, 'PR1M@RY S0N#R V!3WP0RT', BGRA(255, 0, 0, 255));
    FMainBuffer.TextOut(20, 40, 'C00RD: X:??? Y:???', BGRA(255, 0, 0, 255));
  end
  else if FROVModel.IsBlackout then
  begin
    FMainBuffer.TextOut(20, 20, 'SYSTEM OFFLINE: REBOOTING...', BGRA(255, 50, 50, 255));
    FMainBuffer.TextOut(20, 40, 'COORD: OFFLINE', BGRA(150, 150, 150, 255));
  end
  else
  begin
    FMainBuffer.TextOut(20, 20, 'PRIMARY SONAR VIEWPORT', BGRA(0, 255, 255, 255));
    FMainBuffer.TextOut(20, 40, Format('COORD: X:%d Y:%d', [Trunc(FROVModel.X), Trunc(FROVModel.Y)]), BGRA(200, 200, 200, 255));
  end;

  FMainBuffer.FillRect(FMainBuffer.Width - 250, 10, FMainBuffer.Width - 10, 130, BGRA(0, 0, 0, 180), dmDrawWithTransparency);

  if FROVModel.IsGlitching and (Random(10) > 6) then
    HUDColor := BGRA(255, 0, 0, 255)
  else
    HUDColor := BGRA(255, 255, 255, 255);

  Txt := Format('DEPTH: %.1f M', [FROVModel.Depth]);
  FMainBuffer.TextOut(FMainBuffer.Width - 230, 20, Txt, HUDColor);

  Txt := Format('HULL INTEGRITY: %.0f%%', [FROVModel.HullIntegrity]);
  if FROVModel.HullIntegrity < 30 then
    FMainBuffer.TextOut(FMainBuffer.Width - 230, 45, Txt, BGRA(255, 50, 50, 255))
  else
    FMainBuffer.TextOut(FMainBuffer.Width - 230, 45, Txt, BGRA(255, 180, 0, 255));

  Txt := Format('POWER: %.0f%%', [FROVModel.Power]);
  FMainBuffer.TextOut(FMainBuffer.Width - 230, 70, Txt, BGRA(0, 255, 100, 255));

  // Tampilkan Cooldown Senjata
  if FROVModel.EMPCooldownTimer > 0 then
    FMainBuffer.TextOut(FMainBuffer.Width - 230, 95, Format('EMP CD: %.0fs', [FROVModel.EMPCooldownTimer]), BGRA(255, 100, 100, 255))
  else
    FMainBuffer.TextOut(FMainBuffer.Width - 230, 95, 'EMP CD: READY', BGRA(100, 255, 100, 255));

  if FROVModel.IsExtracting then
  begin
    FMainBuffer.FillRect((FMainBuffer.Width div 2) - 80, (FMainBuffer.Height div 2) - 40,
                         (FMainBuffer.Width div 2) + 80, (FMainBuffer.Height div 2) - 15,
                         BGRA(0,0,0,180), dmDrawWithTransparency);
    FMainBuffer.TextOut((FMainBuffer.Width div 2) - 65, (FMainBuffer.Height div 2) - 35,
                        'ARM DEPLOYED', BGRA(255, 200, 0, 255));
  end;
end;

procedure TSonarRenderer.DrawTelemetryOverlay;
var
  Txt: String;
  PressureVal: Single;
  TempVal: Single;
  DescentVal: Single;
  TetherText: String;
  TetherColor: TBGRAPixel;
begin
  FMainBuffer.FontHeight := 14;
  FMainBuffer.FontName := 'Consolas';
  FMainBuffer.FontAntialias := True;

  // Kotak latar belakang transparan di sudut kiri bawah
  FMainBuffer.FillRect(10, FMainBuffer.Height - 130, 280, FMainBuffer.Height - 10, BGRA(0, 0, 0, 180), dmDrawWithTransparency);

  // Kalkulasi nilai telemetri langsung dari model ROV
  PressureVal := 0.1 + (FROVModel.Depth * 0.0101);
  TempVal := Max(1.0, 15.0 - (FROVModel.Depth * 0.005));
  DescentVal := 0.0; // Atau ambil dari kecepatan vertikal jika ada

  Txt := Format('PRESSURE: %.2f MPa', [PressureVal]);
  FMainBuffer.TextOut(20, FMainBuffer.Height - 120, Txt, BGRA(255, 255, 255, 255));

  Txt := Format('TEMP: %.1f °C', [TempVal]);
  FMainBuffer.TextOut(20, FMainBuffer.Height - 95, Txt, BGRA(255, 255, 255, 255));

  Txt := Format('DESCENT RATE: %.1f m/s', [DescentVal]);
  FMainBuffer.TextOut(20, FMainBuffer.Height - 70, Txt, BGRA(255, 255, 255, 255));

  // Status Tether / Lambung
  if FROVModel.HullIntegrity < 30 then
  begin
    TetherText := 'TETHER: CRITICAL';
    TetherColor := BGRA(255, 50, 50, 255);
  end
  else if FROVModel.HullIntegrity < 75 then
  begin
    TetherText := 'TETHER: WARNING';
    TetherColor := BGRA(0, 140, 255, 255);
  end
  else
  begin
    TetherText := 'TETHER: OK [STABLE]';
    TetherColor := BGRA(0, 255, 100, 255);
  end;

  FMainBuffer.TextOut(20, FMainBuffer.Height - 45, TetherText, TetherColor);
end;

procedure TSonarRenderer.DrawDamageVignette;
begin
  if FROVModel.HullIntegrity < 50.0 then
  begin
    FMainBuffer.FillRect(0, 0, FMainBuffer.Width, FMainBuffer.Height,
                         BGRA(255, 0, 0, Trunc(150 * (1.0 - (FROVModel.HullIntegrity / 50.0)))),
                         dmDrawWithTransparency);
  end;
end;

procedure TSonarRenderer.RenderFrame(DeltaTimeMS: UInt32);
begin
  if (FMainBuffer.Width <> FTargetBox.Width) or (FMainBuffer.Height <> FTargetBox.Height) then
  begin
    FMainBuffer.SetSize(FTargetBox.Width, FTargetBox.Height);
    FStaticTerrain.SetSize(FTargetBox.Width, FTargetBox.Height);
    FTerrainNeedsUpdate := True;
  end;

  if (Abs(FLastROVX - Trunc(FROVModel.X)) >= UPDATE_THRESHOLD) or
     (Abs(FLastROVY - Trunc(FROVModel.Y)) >= UPDATE_THRESHOLD) or
     FTerrainNeedsUpdate then
  begin
    UpdateStaticTerrain;
  end;

  // --- CEK BLACKOUT ---
  if FROVModel.IsBlackout then
  begin
    // Jika Blackout, layar sepenuhnya hitam gelap, radar mati
    FMainBuffer.Fill(BGRA(0, 0, 0, 255));

    // Beri efek kilat statis EMP di frame pertama
    if Random(10) > 8 then
      FMainBuffer.Fill(BGRA(255, 255, 255, Random(50)));

    DrawScanlines; // Terapkan scanline bahkan saat blackout
    DrawDamageVignette; // HUD & Damage tetap nyala walau radar mati
    DrawHUDOverlay;
  end
  else
  begin
    // Mode Normal
    FMainBuffer.PutImage(0, 0, FStaticTerrain, dmSet);
    DrawCoordinateGrid;
    DrawRadarConcentric;
    DrawAnomalies;
    DrawDecoy;
    DrawHostiles;
    DrawGlitchEffects;
    DrawSweepTrail(DeltaTimeMS / 1000.0);
    DrawScanlines; // Panggil Scanlines setelah semua elemen dirender, tapi sebelum vignette/HUD
    DrawDamageVignette;
    DrawHUDOverlay;
    DrawTelemetryOverlay;
  end;

  FMainBuffer.Draw(FTargetBox.Canvas, 0, 0, False);
end;

end.
