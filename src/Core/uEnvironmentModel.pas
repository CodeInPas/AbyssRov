unit uEnvironmentModel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections;

type
  { Tambahan atBlackBox untuk fitur High Risk High Reward }
  TAnomalyType = (atBiomatter, atRareOre, atUnknown, atBlackBox);

  { Data structure untuk menyimpan informasi objek anomali yang dapat diambil }
  TAnomaly = record
    ID: Integer;
    X, Y: Integer;
    Depth: Single;
    AnomalyType: TAnomalyType;
    Secured: Boolean;
  end;

  { Data structure untuk entitas biologis bergerak (Leviathan / Predator) }
  THostileEntity = record
    ID: Integer;
    X, Y: Single;
    PatrolX, PatrolY: Single; // Titik pusat area patroli
    PatrolAngle: Single;      // Sudut rotasi saat patroli melingkar
    Speed: Single;
    IsHunting: Boolean;       // Status memburu ROV (dipicu kebisingan)
    StunTimer: Single;        // Tambahan untuk fitur EMP Burst (waktu kelumpuhan)
  end;

  TAnomalyList = specialize TList<TAnomaly>;
  THostileList = specialize TList<THostileEntity>;

  { TEnvironmentModel:
    Menangani matriks ruang 2D dan Procedural Generation kontur bawah laut.
    Dirancang tanpa menyimpan seluruh peta di RAM (Zero-memory footprint untuk terrain). }
  TEnvironmentModel = class
  private
    FSeed: Integer;
    FActiveAnomalies: TAnomalyList;
    FActiveHostiles: THostileList; // Daftar monster aktif di chunk ini

    // Status Modul Pertahanan Aktif
    FDecoyActive: Boolean;
    FDecoyX, FDecoyY: Single;
    FDecoyTimer: Single;

    { Fungsi Hash Pseudo-Random untuk menghasilkan nilai konsisten berdasarkan koordinat }
    function Hash2D(X, Y: Integer): Single;

    { Interpolasi pergerakan nilai noise agar kontur tebing terlihat halus (Smooth Terrain) }
    function SmoothNoise(X, Y: Single): Single;
  public
    constructor Create(ASeed: Integer);
    destructor Destroy; override;

    { Mendapatkan tingkat kepadatan tebing/batu di koordinat X,Y tertentu.
      Nilai kembalian: 0.0 (Air kosong) hingga 1.0 (Batu padat/Solid Rock). }
    function GetDensity(X, Y: Integer): Single;

    { Memindai dan mengembalikan list anomali yang berada dalam jangkauan radar Sonar. }
    function GetAnomaliesInRadius(CenterX, CenterY, Radius: Integer; out ResultList: TAnomalyList): Integer;

    { Memindai entitas bergerak (predator) dalam jangkauan Sonar. }
    function GetHostilesInRadius(CenterX, CenterY, Radius: Integer; out ResultList: THostileList): Integer;

    { Membangkitkan anomali & entitas musuh secara prosedural saat ROV memasuki kedalaman (Chunk) baru. }
    procedure GenerateChunk(DepthStart, DepthEnd: Single);

    { Update logika pergerakan musuh (AI) berdasarkan level bising ROV (Stealth Mechanic) }
    procedure UpdateEntities(DeltaSec: Single; ROVX, ROVY: Single; IsNoisy: Boolean);

    { Cek benturan (serangan mematikan) antara ROV dan Leviathan }
    function CheckHostileCollision(ROVX, ROVY: Single; HitRadius: Single): Boolean;

    { --- FITUR ACTIVE COUNTERMEASURES --- }
    { Memicu EMP yang melumpuhkan semua monster di radius tertentu }
    procedure TriggerEMP(CenterX, CenterY, Radius, StunDuration: Single);

    { Memicu Decoy Akustik yang mengalihkan perhatian monster dari ROV }
    procedure TriggerDecoy(DecoyX, DecoyY, Duration: Single);

    // Properti status Decoy (berguna untuk dirender di radar)
    property IsDecoyActive: Boolean read FDecoyActive;
    property DecoyX: Single read FDecoyX;
    property DecoyY: Single read FDecoyY;
  end;

implementation

{ TEnvironmentModel }

constructor TEnvironmentModel.Create(ASeed: Integer);
begin
  inherited Create;
  FSeed := ASeed;
  FActiveAnomalies := TAnomalyList.Create;
  FActiveHostiles := THostileList.Create;
  FDecoyActive := False;
end;

destructor TEnvironmentModel.Destroy;
begin
  FActiveHostiles.Free;
  FActiveAnomalies.Free;
  inherited Destroy;
end;

function TEnvironmentModel.Hash2D(X, Y: Integer): Single;
var
  n: Integer;
begin
  // Formula hash integer bitwise untuk procedural noise O(1)
  n := X + Y * 57 + FSeed * 131;
  n := (n shl 13) xor n;
  Result := (1.0 - ((n * (n * n * 15731 + 789221) + 1376312589) and $7FFFFFFF) / 1073741824.0);
end;

function TEnvironmentModel.SmoothNoise(X, Y: Single): Single;
var
  intX, intY: Integer;
  fracX, fracY: Single;
  v1, v2, v3, v4: Single;
  i1, i2: Single;
begin
  intX := Floor(X);
  intY := Floor(Y);
  fracX := X - intX;
  fracY := Y - intY;

  // Dapatkan sampel titik sudut dari grid terdekat
  v1 := Hash2D(intX, intY);
  v2 := Hash2D(intX + 1, intY);
  v3 := Hash2D(intX, intY + 1);
  v4 := Hash2D(intX + 1, intY + 1);

  // Interpolasi Cosine untuk transisi kurva yang lebih organik (mengurangi jagged edge)
  fracX := (1 - Cos(fracX * Pi)) * 0.5;
  fracY := (1 - Cos(fracY * Pi)) * 0.5;

  i1 := v1 * (1 - fracX) + v2 * fracX;
  i2 := v3 * (1 - fracX) + v4 * fracX;

  Result := i1 * (1 - fracY) + i2 * fracY;
end;

function TEnvironmentModel.GetDensity(X, Y: Integer): Single;
var
  NoiseValue: Single;
  Scale: Single;
begin
  // Skala zoom dari peta kontur (Semakin kecil nilai = tebing semakin besar/lebar)
  Scale := 0.03;
  NoiseValue := SmoothNoise(X * Scale, Y * Scale);

  // Normalisasi hasil dari [-1.0 .. 1.0] menjadi rentang [0.0 .. 1.0]
  Result := (NoiseValue + 1.0) * 0.5;
end;

function TEnvironmentModel.GetAnomaliesInRadius(CenterX, CenterY, Radius: Integer; out ResultList: TAnomalyList): Integer;
var
  i: Integer;
  DistSq, RadiusSq: Integer;
  Anom: TAnomaly;
begin
  ResultList.Clear;
  RadiusSq := Radius * Radius; // Optimalisasi: Gunakan squared distance

  for i := 0 to FActiveAnomalies.Count - 1 do
  begin
    Anom := FActiveAnomalies[i];
    if Anom.Secured then Continue; // Abaikan sampel yang sudah diambil

    DistSq := Sqr(Anom.X - CenterX) + Sqr(Anom.Y - CenterY);
    if DistSq <= RadiusSq then
      ResultList.Add(Anom);
  end;

  Result := ResultList.Count;
end;

function TEnvironmentModel.GetHostilesInRadius(CenterX, CenterY, Radius: Integer; out ResultList: THostileList): Integer;
var
  i: Integer;
  DistSq, RadiusSq: Single;
  Hostile: THostileEntity;
begin
  ResultList.Clear;
  RadiusSq := Sqr(Single(Radius));

  for i := 0 to FActiveHostiles.Count - 1 do
  begin
    Hostile := FActiveHostiles[i];
    DistSq := Sqr(Hostile.X - CenterX) + Sqr(Hostile.Y - CenterY);
    if DistSq <= RadiusSq then
      ResultList.Add(Hostile);
  end;

  Result := ResultList.Count;
end;

procedure TEnvironmentModel.GenerateChunk(DepthStart, DepthEnd: Single);
var
  i, AnomalyCount, HostileCount: Integer;
  NewAnomaly: TAnomaly;
  NewHostile: THostileEntity;
begin
  // Dynamic Chunking: Hapus entitas lama untuk mencegah Memory Leak
  FActiveAnomalies.Clear;
  FActiveHostiles.Clear;
  FDecoyActive := False; // Matikan decoy saat pindah area

  // Atur seed randomizer spesifik untuk chunk kedalaman ini
  RandSeed := FSeed + Trunc(DepthStart);

  // 1. Spawn Statis (Anomali Ore/Biomatter)
  AnomalyCount := Random(5) + 3;
  for i := 0 to AnomalyCount - 1 do
  begin
    NewAnomaly.ID := FSeed + Trunc(DepthStart) + i;
    NewAnomaly.X := Random(4000) - 2000;
    NewAnomaly.Y := Random(4000) - 2000;
    NewAnomaly.Depth := DepthStart + Random(Trunc(DepthEnd - DepthStart));
    // Hanya membangkitkan Biomatter (0), RareOre (1), Unknown (2) secara reguler
    NewAnomaly.AnomalyType := TAnomalyType(Random(3));
    NewAnomaly.Secured := False;

    // Menempel pada tebing
    if GetDensity(NewAnomaly.X, NewAnomaly.Y) > 0.65 then
      FActiveAnomalies.Add(NewAnomaly);
  end;

  // 2. Spawn Super Langka: Bangkai ROV / Black Box (15% peluang per chunk kedalaman)
  if Random(100) < 15 then
  begin
    NewAnomaly.ID := FSeed * 3 + Trunc(DepthStart);
    NewAnomaly.X := Random(4000) - 2000;
    NewAnomaly.Y := Random(4000) - 2000;
    NewAnomaly.Depth := DepthStart + Random(Trunc(DepthEnd - DepthStart));
    NewAnomaly.AnomalyType := atBlackBox; // Bangkai ROV
    NewAnomaly.Secured := False;

    // Black Box nyangkut di karang dasar
    if GetDensity(NewAnomaly.X, NewAnomaly.Y) > 0.5 then
      FActiveAnomalies.Add(NewAnomaly);
  end;

  // 3. Spawn Dinamis (Hostile Leviathan)
  if DepthStart >= 1000.0 then // Predator baru muncul di kedalaman >= 1000 meter
  begin
    HostileCount := Random(3) + 1; // 1 hingga 3 predator per chunk
    for i := 0 to HostileCount - 1 do
    begin
      NewHostile.ID := FSeed * 2 + Trunc(DepthStart) + i;

      // Pastikan titik pusat patroli berada di air lepas (tidak menancap di karang)
      repeat
        NewHostile.PatrolX := Random(4000) - 2000;
        NewHostile.PatrolY := Random(4000) - 2000;
      until GetDensity(Trunc(NewHostile.PatrolX), Trunc(NewHostile.PatrolY)) < 0.4;

      NewHostile.X := NewHostile.PatrolX;
      NewHostile.Y := NewHostile.PatrolY;
      NewHostile.PatrolAngle := Random(360);
      NewHostile.Speed := 40.0 + Random(20); // Kecepatan gerak dasar
      NewHostile.IsHunting := False;
      NewHostile.StunTimer := 0.0; // Normal, tidak lumpuh

      FActiveHostiles.Add(NewHostile);
    end;
  end;
end;

procedure TEnvironmentModel.TriggerEMP(CenterX, CenterY, Radius, StunDuration: Single);
var
  i: Integer;
  H: THostileEntity;
  DistSq, RadiusSq: Single;
begin
  RadiusSq := Sqr(Radius);
  for i := 0 to FActiveHostiles.Count - 1 do
  begin
    H := FActiveHostiles[i];
    DistSq := Sqr(H.X - CenterX) + Sqr(H.Y - CenterY);
    if DistSq <= RadiusSq then
    begin
      H.StunTimer := StunDuration; // Lumpuhkan monster
      H.IsHunting := False;        // Lepaskan aggro
      FActiveHostiles[i] := H;
    end;
  end;
end;

procedure TEnvironmentModel.TriggerDecoy(DecoyX, DecoyY, Duration: Single);
begin
  FDecoyActive := True;
  FDecoyX := DecoyX;
  FDecoyY := DecoyY;
  FDecoyTimer := Duration;
end;

procedure TEnvironmentModel.UpdateEntities(DeltaSec: Single; ROVX, ROVY: Single; IsNoisy: Boolean);
var
  i: Integer;
  H: THostileEntity;
  AngleRad: Single;
  DistX, DistY, DistTotal: Single;
  DirX, DirY: Single;
  TargetX, TargetY: Single;
  TargetIsNoisy: Boolean;
begin
  // Update durasi Decoy
  if FDecoyActive then
  begin
    FDecoyTimer := Max(0.0, FDecoyTimer - DeltaSec);
    if FDecoyTimer <= 0 then FDecoyActive := False;
  end;

  for i := 0 to FActiveHostiles.Count - 1 do
  begin
    H := FActiveHostiles[i]; // Ambil data record

    // Cek efek stun dari EMP
    if H.StunTimer > 0 then
    begin
      H.StunTimer := Max(0.0, H.StunTimer - DeltaSec);
      FActiveHostiles[i] := H;
      Continue; // Lewati AI pergerakan karena sedang lumpuh
    end;

    // Tentukan Target AI: Apakah mengejar Decoy atau mengejar ROV
    if FDecoyActive then
    begin
      TargetX := FDecoyX;
      TargetY := FDecoyY;
      TargetIsNoisy := True; // Decoy sangat berisik dan agresif menarik perhatian
    end
    else
    begin
      TargetX := ROVX;
      TargetY := ROVY;
      TargetIsNoisy := IsNoisy;
    end;

    DistX := TargetX - H.X;
    DistY := TargetY - H.Y;
    DistTotal := Sqrt(Sqr(DistX) + Sqr(DistY));

    // QA BALANCE FIX: Radius pendengaran diturunkan dari 1200 menjadi 850 unit
    // Ini memberi jeda kepada pemain untuk mematikan sonar dan menghilang dari kejaran
    if TargetIsNoisy and (DistTotal < 850.0) then
      H.IsHunting := True
    else if DistTotal > 1500.0 then
      H.IsHunting := False; // Terlalu jauh, kehilangan jejak

    if H.IsHunting then
    begin
      // AI Hunting: Mengejar langsung ke target dengan kecepatan agresif
      if DistTotal > 0 then
      begin
        DirX := DistX / DistTotal;
        DirY := DistY / DistTotal;
        H.X := H.X + (DirX * (H.Speed * 1.8) * DeltaSec);
        H.Y := H.Y + (DirY * (H.Speed * 1.8) * DeltaSec);
      end;
    end
    else
    begin
      // AI Patroli: Berputar mengelilingi titik teritori (Stealth Mode aman)
      H.PatrolAngle := H.PatrolAngle + (20.0 * DeltaSec);
      if H.PatrolAngle >= 360.0 then H.PatrolAngle := H.PatrolAngle - 360.0;

      AngleRad := DegToRad(H.PatrolAngle);
      // Bergerak mengorbit sejauh radius 300 unit
      H.X := H.PatrolX + Cos(AngleRad) * 300.0;
      H.Y := H.PatrolY + Sin(AngleRad) * 300.0;
    end;

    // Terapkan perubahan kembali ke list (karena THostileEntity adalah Record/Value-type)
    FActiveHostiles[i] := H;
  end;
end;

function TEnvironmentModel.CheckHostileCollision(ROVX, ROVY: Single; HitRadius: Single): Boolean;
var
  i: Integer;
  H: THostileEntity;
  DistSq, HitRadiusSq: Single;
begin
  Result := False;
  HitRadiusSq := Sqr(HitRadius);

  for i := 0 to FActiveHostiles.Count - 1 do
  begin
    H := FActiveHostiles[i];
    if H.StunTimer > 0 then Continue; // Monster lumpuh tidak bisa melukai ROV

    DistSq := Sqr(H.X - ROVX) + Sqr(H.Y - ROVY);
    // Jika Leviathan berhasil menyentuh ROV
    if DistSq <= HitRadiusSq then
    begin
      Result := True;
      Break;
    end;
  end;
end;

end.
