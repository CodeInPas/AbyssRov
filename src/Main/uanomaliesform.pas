unit uAnomaliesForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, DBGrids, ExtCtrls,
  bsbutton, Db, sqldb, sqlite3conn;

type

  { TAnomaliesForm }

  TAnomaliesForm = class(TForm)
    btnClosePopup: TBsButton;
    dbgPopupAnomalies: TDBGrid;
    dsPopupAnomalies: TDataSource;
    PopupConn: TSQLite3Connection;
    PopupQuery: TSQLQuery;
    PopupTrans: TSQLTransaction;

    procedure FormCreate(Sender: TObject);
    procedure btnClosePopupClick(Sender: TObject);
    procedure BtnMouseEnter(Sender: TObject);
    procedure BtnMouseLeave(Sender: TObject);
  private
    DBPath: String;
  public
    procedure SetDatabasePath(const APath: String);
    procedure RefreshData;
  end;

var
  AnomaliesForm: TAnomaliesForm;

implementation

{$R *.lfm}

procedure TAnomaliesForm.FormCreate(Sender: TObject);
begin
  Self.Color := 1380101;
  Self.Font.Name := 'Consolas';
  Self.Font.Color := clWhite;
end;

procedure TAnomaliesForm.SetDatabasePath(const APath: String);
begin
  DBPath := APath;
  PopupConn.DatabaseName := DBPath;
  PopupQuery.SQL.Text := 'SELECT SampleID, DepthFound, AnomalyType, IntegrityAtExtraction FROM Extracted_Anomalies ORDER BY SampleID DESC';
  try
    PopupConn.Connected := True;
    PopupQuery.Open;
  except
  end;
end;

procedure TAnomaliesForm.RefreshData;
begin
  if PopupQuery.Active then
  begin
    PopupQuery.Close;
    PopupQuery.Open;
  end;
end;

procedure TAnomaliesForm.btnClosePopupClick(Sender: TObject);
begin
  Close;
end;

procedure TAnomaliesForm.BtnMouseEnter(Sender: TObject);
begin
  if Sender is TPanel then
  begin
    TPanel(Sender).Color := $003A2A1A;
    TPanel(Sender).Font.Color := clWhite;
  end;
end;

procedure TAnomaliesForm.BtnMouseLeave(Sender: TObject);
begin
  if Sender is TPanel then
  begin
    TPanel(Sender).Color := 1380101;
    TPanel(Sender).Font.Color := clYellow;
  end;
end;

end.
