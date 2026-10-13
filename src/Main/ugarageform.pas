unit uGarageForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  uDatabaseManager;

type
  TGarageForm = class(TForm)
    lblTitle: TLabel;
    lblPoints: TLabel;
    lblHullInfo: TLabel;
    lblBatteryInfo: TLabel;
    lblThrusterInfo: TLabel;
    lblDecoyInfo: TLabel; // Label Info Decoy
    lblEMPInfo: TLabel;   // Label Info EMP

    // Ubah TButton menjadi TPanel untuk gaya Terminal UI
    btnUpgradeHull: TPanel;
    btnUpgradeBattery: TPanel;
    btnUpgradeThruster: TPanel;
    btnUpgradeDecoy: TPanel; // Tombol Upgrade Decoy
    btnUpgradeEMP: TPanel;   // Tombol Upgrade EMP
    btnClose: TPanel;

    procedure FormCreate(Sender: TObject);
    procedure btnUpgradeHullClick(Sender: TObject);
    procedure btnUpgradeBatteryClick(Sender: TObject);
    procedure btnUpgradeThrusterClick(Sender: TObject);
    procedure btnUpgradeDecoyClick(Sender: TObject);
    procedure btnUpgradeEMPClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);

    // Hover Effects
    procedure BtnMouseEnter(Sender: TObject);
    procedure BtnMouseLeave(Sender: TObject);
  private
    FDBManager: TDatabaseManager;
    FSpecs: TROVSpecs;
    procedure RefreshUI;
  public
    procedure SetDatabase(ADBManager: TDatabaseManager);
  end;

var
  GarageForm: TGarageForm;

implementation

{$R *.lfm}

procedure TGarageForm.FormCreate(Sender: TObject);
begin
  FDBManager := nil;
end;

procedure TGarageForm.SetDatabase(ADBManager: TDatabaseManager);
begin
  FDBManager := ADBManager;
  RefreshUI;
end;

procedure TGarageForm.RefreshUI;
begin
  if FDBManager = nil then Exit;

  FSpecs := FDBManager.GetROVSpecs;

  lblPoints.Caption := Format('RESEARCH POINTS (RP): %d', [FSpecs.ResearchPoints]);
  lblHullInfo.Caption := Format('HULL REINFORCEMENT [Level %d] (Cost: %d RP)', [FSpecs.HullLevel, FSpecs.HullLevel * 100]);
  lblBatteryInfo.Caption := Format('BATTERY EFFICIENCY [Level %d] (Cost: %d RP)', [FSpecs.BatteryLevel, FSpecs.BatteryLevel * 75]);
  lblThrusterInfo.Caption := Format('THRUSTER POWER [Level %d] (Cost: %d RP)', [FSpecs.ThrusterLevel, FSpecs.ThrusterLevel * 90]);

  // Biaya modul pertahanan dikalikan (Level + 1) karena dimulai dari level 0
  lblDecoyInfo.Caption := Format('ACOUSTIC DECOY MOD [Level %d] (Cost: %d RP)', [FSpecs.DecoyLevel, (FSpecs.DecoyLevel + 1) * 120]);
  lblEMPInfo.Caption := Format('EMP BURST MOD [Level %d] (Cost: %d RP)', [FSpecs.EMPLevel, (FSpecs.EMPLevel + 1) * 150]);
end;

// Efek Hover Neon (Menyala saat ditunjuk)
procedure TGarageForm.BtnMouseEnter(Sender: TObject);
begin
  if (Sender is TPanel) and TPanel(Sender).Enabled then
  begin
    TPanel(Sender).Color := $003A2A1A; // Navy terang
    TPanel(Sender).Font.Color := clWhite;
  end;
end;

// Efek Hover (Kembali gelap saat ditinggalkan)
procedure TGarageForm.BtnMouseLeave(Sender: TObject);
begin
  if (Sender is TPanel) and TPanel(Sender).Enabled then
  begin
    TPanel(Sender).Color := $00150F05; // Base color
    if Sender = btnClose then
      TPanel(Sender).Font.Color := clYellow
    else
      TPanel(Sender).Font.Color := clAqua;
  end;
end;

procedure TGarageForm.btnUpgradeHullClick(Sender: TObject);
var
  Cost: Integer;
begin
  if FDBManager = nil then Exit;
  Cost := FSpecs.HullLevel * 100;

  if FSpecs.ResearchPoints >= Cost then
  begin
    FSpecs.ResearchPoints := FSpecs.ResearchPoints - Cost;
    FSpecs.HullLevel := FSpecs.HullLevel + 1;
    FDBManager.SaveROVSpecs(FSpecs);
    RefreshUI;
  end
  else
    ShowMessage('INSUFFICIENT RESEARCH POINTS FOR HULL UPGRADE.');
end;

procedure TGarageForm.btnUpgradeBatteryClick(Sender: TObject);
var
  Cost: Integer;
begin
  if FDBManager = nil then Exit;
  Cost := FSpecs.BatteryLevel * 75;

  if FSpecs.ResearchPoints >= Cost then
  begin
    FSpecs.ResearchPoints := FSpecs.ResearchPoints - Cost;
    FSpecs.BatteryLevel := FSpecs.BatteryLevel + 1;
    FDBManager.SaveROVSpecs(FSpecs);
    RefreshUI;
  end
  else
    ShowMessage('INSUFFICIENT RESEARCH POINTS FOR BATTERY UPGRADE.');
end;

procedure TGarageForm.btnUpgradeThrusterClick(Sender: TObject);
var
  Cost: Integer;
begin
  if FDBManager = nil then Exit;
  Cost := FSpecs.ThrusterLevel * 90;

  if FSpecs.ResearchPoints >= Cost then
  begin
    FSpecs.ResearchPoints := FSpecs.ResearchPoints - Cost;
    FSpecs.ThrusterLevel := FSpecs.ThrusterLevel + 1;
    FDBManager.SaveROVSpecs(FSpecs);
    RefreshUI;
  end
  else
    ShowMessage('INSUFFICIENT RESEARCH POINTS FOR THRUSTER UPGRADE.');
end;

procedure TGarageForm.btnUpgradeDecoyClick(Sender: TObject);
var
  Cost: Integer;
begin
  if FDBManager = nil then Exit;
  Cost := (FSpecs.DecoyLevel + 1) * 120;

  if FSpecs.ResearchPoints >= Cost then
  begin
    FSpecs.ResearchPoints := FSpecs.ResearchPoints - Cost;
    FSpecs.DecoyLevel := FSpecs.DecoyLevel + 1;
    FDBManager.SaveROVSpecs(FSpecs);
    RefreshUI;
  end
  else
    ShowMessage('INSUFFICIENT RESEARCH POINTS FOR DECOY MODULE.');
end;

procedure TGarageForm.btnUpgradeEMPClick(Sender: TObject);
var
  Cost: Integer;
begin
  if FDBManager = nil then Exit;
  Cost := (FSpecs.EMPLevel + 1) * 150;

  if FSpecs.ResearchPoints >= Cost then
  begin
    FSpecs.ResearchPoints := FSpecs.ResearchPoints - Cost;
    FSpecs.EMPLevel := FSpecs.EMPLevel + 1;
    FDBManager.SaveROVSpecs(FSpecs);
    RefreshUI;
  end
  else
    ShowMessage('INSUFFICIENT RESEARCH POINTS FOR EMP MODULE.');
end;

procedure TGarageForm.btnCloseClick(Sender: TObject);
begin
  Close; // Tutup form Garasi
end;

end.
