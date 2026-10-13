unit uCameraRenderer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, ExtCtrls, Math,
  BGRABitmap, BGRABitmapTypes, uEnvironmentModel, uROVModel;

type
  { TCameraRenderer: Menyajikan visual feed 3D palsu (Raycaster) dari pandangan depan ROV }
  TCameraRenderer = class
  private
    FTargetBox: TPaintBox;
    FEnvModel: TEnvironmentModel;
    FROVModel: TROVModel;
    FMainBuffer: TBGRABitmap;

    // Struktur Partikel Air (Marine Snow)
    type
      TSnow = record
        X, Y, Speed, Size: Single;
      end;
    var
      FSnow: array[0..59] of TSnow; // 60 partikel kotoran laut

    procedure InitMarineSnow;
    procedure DrawMarineSnow(DeltaSec: Single);
    procedure DrawPseudo3D(DeltaSec: Single);
    procedure DrawStaticNoiseAndGlitch;
    procedure DrawHUDOverlay;
  public
    constructor Create(APaintBox: TPaintBox; AEnv: TEnvironmentModel; AROV: TROVModel);
    destructor Destroy; override;
    procedure RenderFrame(DeltaTimeMS: UInt32);
  end;

implementation

{ TCameraRenderer }

constructor TCameraRenderer.Create(APaintBox: TPaintBox; AEnv: TEnvironmentModel; AROV: TROVModel);
var
  InitW, InitH: Integer;
begin
  inherited Create;
  FTargetBox := APaintBox;
  FEnvModel := AEnv;
  FROVModel := AROV;

  // --- BUG FIX: Pengaman (Failsafe) jika TPaintBox belum terhubung (nil) ---
  InitW := 1;
  InitH := 1;
  if Assigned(FTargetBox) then
  begin
    if FTargetBox.Width > 0 then InitW := FTargetBox.Width;
    if FTargetBox.Height > 0 then InitH := FTargetBox.Height;
  end;

  FMainBuffer := TBGRABitmap.Create(InitW, InitH, BGRA(0,0,0,255));
  InitMarineSnow;
end;

destructor TCameraRenderer.Destroy;
begin
  FMainBuffer.Free;
  inherited Destroy;
end;

procedure TCameraRenderer.InitMarineSnow;
var
  i: Integer;
begin
  for i := Low(FSnow) to High(FSnow) do
  begin
    FSnow[i].X := Random(800); // Asumsi lebar awal
    FSnow[i].Y := Random(600);
    FSnow[i].Speed := 10.0 + Random(30);
    FSnow[i].Size := 1.0 + Random(3);
  end;
end;

procedure TCameraRenderer.DrawPseudo3D(DeltaSec: Single);
var
  x: Integer;
  RayAngle, RayX, RayY, Dist, MaxDist: Single;
  WallHeight: Integer;
  Hit: Boolean;
  StepSize: Single;
  Col: TBGRAPixel;
  Intensity: Byte;
  CorrectedDist: Single;
  CenterY: Integer;
begin
  MaxDist := 250.0; // Jarak pandang maksimal lampu sorot kamera
  StepSize := 2.5;  // Akurasi raycast (lebih kecil = lebih mulus tapi berat)
  CenterY := FMainBuffer.Height div 2;

  // Latar belakang pitch black (kegelapan abisal)
  FMainBuffer.Fill(BGRA(2, 5, 8, 255));

  // Tembakkan sinar untuk setiap pixel horizontal di layar kamera (FOV 60 derajat)
  for x := 0 to FMainBuffer.Width - 1 do
  begin
    // Hitung sudut sinar (-30 hingga +30 derajat dari arah hadap ROV)
    RayAngle := FROVModel.Heading - 30.0 + (x / FMainBuffer.Width) * 60.0;
    RayX := FROVModel.X;
    RayY := FROVModel.Y;
    Dist := 0;
    Hit := False;

    // Raycasting: Maju perlahan sampai menabrak dinding karang
    while (Dist < MaxDist) and not Hit do
    begin
      RayX := RayX + Cos(DegToRad(RayAngle)) * StepSize;
      RayY := RayY + Sin(DegToRad(RayAngle)) * StepSize;
      Dist := Dist + StepSize;

      // Jika kepadatan di titik ini > 0.45, berarti menabrak tebing
      if FEnvModel.GetDensity(Trunc(RayX), Trunc(RayY)) > 0.45 then
        Hit := True;
    end;

    // Jika sinar menabrak tebing, gambarkan garis vertikal (dinding 3D)
    if Hit then
    begin
      // Koreksi distorsi lensa fish-eye
      CorrectedDist := Dist * Cos(DegToRad(RayAngle - FROVModel.Heading));
      if CorrectedDist < 1.0 then CorrectedDist := 1.0;

      // Tinggi dinding di layar berdasarkan jarak
      WallHeight := Trunc((FMainBuffer.Height / CorrectedDist) * 35.0);
      if WallHeight > FMainBuffer.Height then WallHeight := FMainBuffer.Height;

      // Intensitas lampu sorot: Semakin jauh semakin gelap gulita
      Intensity := Trunc(255 * (1.0 - (Dist / MaxDist)));
      Col := BGRA(0, Intensity div 2, Intensity div 3, 255); // Warna lumut redup

      // Gambar potongan dinding
      FMainBuffer.DrawLineAntialias(x, CenterY - (WallHeight div 2),
                                    x, CenterY + (WallHeight div 2),
                                    Col, 1.0);
    end;
  end;
end;

procedure TCameraRenderer.DrawMarineSnow(DeltaSec: Single);
var
  i: Integer;
  SnowAlpha: Byte;
begin
  for i := Low(FSnow) to High(FSnow) do
  begin
    // Partikel melayang berlawanan dengan arah gerak ROV
    FSnow[i].Y := FSnow[i].Y - (FSnow[i].Speed * DeltaSec);

    if FSnow[i].Y < 0 then
    begin
      FSnow[i].Y := FMainBuffer.Height;
      FSnow[i].X := Random(FMainBuffer.Width);
    end;

    SnowAlpha := Trunc(100 * (FSnow[i].Size / 4.0));
    FMainBuffer.EllipseAntialias(FSnow[i].X, FSnow[i].Y, FSnow[i].Size, FSnow[i].Size,
                                 BGRA(200, 255, 200, SnowAlpha), 1.0, BGRA(200, 255, 200, SnowAlpha));
  end;
end;

procedure TCameraRenderer.DrawStaticNoiseAndGlitch;
var
  i, rx, ry, BlockHeight: Integer;
begin
  // Efek Noise Kamera Bawah Laut Konstan
  for i := 0 to 150 do
  begin
    rx := Random(FMainBuffer.Width);
    ry := Random(FMainBuffer.Height);
    FMainBuffer.SetPixel(rx, ry, BGRA(255, 255, 255, 30));
  end;

  // Garis Scanline tebal gaya CRT CCTV
  ry := 0;
  while ry < FMainBuffer.Height do
  begin
    FMainBuffer.DrawLineAntialias(0, ry, FMainBuffer.Width, ry, BGRA(0, 0, 0, 60), 1.5);
    Inc(ry, 4);
  end;

  // Efek Glitch Magnetik (Distorsi Sinyal)
  if FROVModel.IsGlitching or FROVModel.IsBlackout then
  begin
    for i := 0 to 8 do
    begin
      rx := Random(FMainBuffer.Width);
      ry := Random(FMainBuffer.Height);
      BlockHeight := Random(15) + 5;
      FMainBuffer.FillRect(0, ry, FMainBuffer.Width, ry + BlockHeight, BGRA(255, 255, 255, 40), dmDrawWithTransparency);
    end;
  end;
end;

procedure TCameraRenderer.DrawHUDOverlay;
begin
  FMainBuffer.FontHeight := 12;
  FMainBuffer.FontName := 'Consolas';
  FMainBuffer.FontAntialias := True;

  // Indikator Perekaman Kamera
  if GetTickCount64 mod 1000 > 500 then
    FMainBuffer.TextOut(10, 10, 'REC *', BGRA(255, 50, 50, 255));

  if FROVModel.IsBlackout then
  begin
    FMainBuffer.Fill(BGRA(0, 0, 0, 230)); // Gelapkan layar
    FMainBuffer.TextOut(FMainBuffer.Width div 2 - 40, FMainBuffer.Height div 2, 'NO SIGNAL', BGRA(200, 200, 200, 255));
  end
  else if FROVModel.IsGlitching then
  begin
    FMainBuffer.TextOut(10, FMainBuffer.Height - 25, 'SYS WARN: MAG INTERFERENCE', BGRA(255, 255, 0, 255));
  end
  else
  begin
    FMainBuffer.TextOut(10, FMainBuffer.Height - 25, 'VISUAL FEED: SECURE', BGRA(0, 255, 100, 150));
  end;
end;

procedure TCameraRenderer.RenderFrame(DeltaTimeMS: UInt32);
begin
  // --- BUG FIX: Jangan coba menggambar jika komponen UI belum dibuat ---
  if not Assigned(FTargetBox) then Exit;

  if (FMainBuffer.Width <> FTargetBox.Width) or (FMainBuffer.Height <> FTargetBox.Height) then
  begin
    if (FTargetBox.Width > 0) and (FTargetBox.Height > 0) then
    begin
      FMainBuffer.SetSize(FTargetBox.Width, FTargetBox.Height);
      InitMarineSnow;
    end
    else Exit; // Tunggu hingga ukuran tidak 0
  end;

  if (FMainBuffer.Width <= 1) or (FMainBuffer.Height <= 1) then Exit;

  DrawPseudo3D(DeltaTimeMS / 1000.0);
  DrawMarineSnow(DeltaTimeMS / 1000.0);
  DrawStaticNoiseAndGlitch;
  DrawHUDOverlay;

  FMainBuffer.Draw(FTargetBox.Canvas, 0, 0, False);
end;

end.
