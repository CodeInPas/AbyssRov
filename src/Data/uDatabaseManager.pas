unit uDatabaseManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sqldb, sqlite3conn, syncobjs, Generics.Collections;

type
  TDBAction = (dbaLogMissionEnd, dbaLogAnomaly, dbaAddPoints);

  TDBTask = record
    Action: TDBAction;
    MissionID: Integer;
    Depth: Single;
    TextData: String;
    Integrity: Single;
  end;

  TDBTaskQueue = specialize TQueue<TDBTask>;

  TROVSpecs = record
    ResearchPoints: Integer;
    HullLevel: Integer;
    BatteryLevel: Integer;
    ThrusterLevel: Integer;
    DecoyLevel: Integer; // Level Modul Pertahanan: Acoustic Decoy
    EMPLevel: Integer;   // Level Modul Pertahanan: EMP Burst
  end;

  TDBWorkerThread = class(TThread)
  private
    FConn: TSQLite3Connection;
    FTrans: TSQLTransaction;
    FQuery: TSQLQuery;
    FQueue: TDBTaskQueue;
    FLock: TCriticalSection;
    FSignal: TEvent;
    FDBPath: String;
    procedure ConnectDB;
    procedure DisconnectDB;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADBPath: String);
    destructor Destroy; override;
    procedure EnqueueTask(const Task: TDBTask);
  end;

  TDatabaseManager = class
  private
    FWorker: TDBWorkerThread;
    FConnSync: TSQLite3Connection;
    FTransSync: TSQLTransaction;
    FQuerySync: TSQLQuery;

    procedure InitializeDatabase;
  public
    constructor Create(const DBPath: String);
    destructor Destroy; override;

    function StartNewMission: Integer;
    procedure EndMission(MissionID: Integer; MaxDepth: Single; const Outcome: String);
    procedure LogAnomaly(MissionID: Integer; DepthFound: Single; const AnomalyType: String; Integrity: Single);
    procedure AddResearchPointsAsync(Points: Integer);

    function GetROVSpecs: TROVSpecs;
    procedure SaveROVSpecs(const Specs: TROVSpecs);
  end;

implementation

{ TDBWorkerThread }

constructor TDBWorkerThread.Create(const ADBPath: String);
begin
  inherited Create(False);
  FDBPath := ADBPath;
  FQueue := TDBTaskQueue.Create;
  FLock := TCriticalSection.Create;
  FSignal := TEvent.Create(nil, False, False, '');
end;

destructor TDBWorkerThread.Destroy;
begin
  Terminate;
  FSignal.SetEvent;
  WaitFor;
  FQueue.Free;
  FLock.Free;
  FSignal.Free;
  inherited Destroy;
end;

procedure TDBWorkerThread.EnqueueTask(const Task: TDBTask);
begin
  FLock.Acquire;
  try
    FQueue.Enqueue(Task);
  finally
    FLock.Release;
  end;
  FSignal.SetEvent;
end;

procedure TDBWorkerThread.ConnectDB;
begin
  FConn := TSQLite3Connection.Create(nil);
  FConn.DatabaseName := FDBPath;
  FTrans := TSQLTransaction.Create(nil);
  FTrans.DataBase := FConn;
  FConn.Transaction := FTrans;

  FQuery := TSQLQuery.Create(nil);
  FQuery.DataBase := FConn;

  FConn.Connected := True;
  // Eksekusi pragma di luar transaksi untuk worker thread
  FConn.ExecuteDirect('PRAGMA busy_timeout = 5000;');
end;

procedure TDBWorkerThread.DisconnectDB;
begin
  FQuery.Free;
  FTrans.Free;
  FConn.Free;
end;

procedure TDBWorkerThread.Execute;
var
  TasksToProcess: specialize TList<TDBTask>;
  Task: TDBTask;
  i: Integer;
begin
  ConnectDB;
  TasksToProcess := specialize TList<TDBTask>.Create;
  try
    while not Terminated do
    begin
      FSignal.WaitFor(100);
      if Terminated then Break;

      FLock.Acquire;
      try
        while FQueue.Count > 0 do
          TasksToProcess.Add(FQueue.Dequeue);
      finally
        FLock.Release;
      end;

      if TasksToProcess.Count > 0 then
      begin
        if FTrans.Active then FTrans.Commit;

        FTrans.StartTransaction;
        try
          for i := 0 to TasksToProcess.Count - 1 do
          begin
            Task := TasksToProcess[i];

            if Task.Action = dbaLogMissionEnd then
            begin
              FQuery.SQL.Text := 'UPDATE Missions SET MaxDepthReached = :Depth, Outcome = :Outcome WHERE MissionID = :ID';
              FQuery.Params.ParamByName('Depth').AsFloat := Task.Depth;
              FQuery.Params.ParamByName('Outcome').AsString := Task.TextData;
              FQuery.Params.ParamByName('ID').AsInteger := Task.MissionID;
              FQuery.ExecSQL;
            end
            else if Task.Action = dbaLogAnomaly then
            begin
              FQuery.SQL.Text := 'INSERT INTO Extracted_Anomalies (MissionID, DepthFound, AnomalyType, IntegrityAtExtraction) ' +
                                 'VALUES (:ID, :Depth, :Type, :Integrity)';
              FQuery.Params.ParamByName('ID').AsInteger := Task.MissionID;
              FQuery.Params.ParamByName('Depth').AsFloat := Task.Depth;
              FQuery.Params.ParamByName('Type').AsString := Task.TextData;
              FQuery.Params.ParamByName('Integrity').AsFloat := Task.Integrity;
              FQuery.ExecSQL;
            end
            else if Task.Action = dbaAddPoints then
            begin
              FQuery.SQL.Text := 'UPDATE ROV_Specs SET ResearchPoints = ResearchPoints + :Pts WHERE ID = 1';
              FQuery.Params.ParamByName('Pts').AsInteger := Task.MissionID;
              FQuery.ExecSQL;
            end;
          end;
          FTrans.Commit;
        except
          FTrans.Rollback;
        end;
        TasksToProcess.Clear;
      end;
    end;
  finally
    TasksToProcess.Free;
    DisconnectDB;
  end;
end;

{ TDatabaseManager }

procedure TDatabaseManager.InitializeDatabase;
begin
  if not FConnSync.Connected then FConnSync.Connected := True;

  if FTransSync.Active then FTransSync.Commit;

  FTransSync.StartTransaction;
  try
    FQuerySync.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS Missions (' +
      'MissionID INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'Timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, ' +
      'MaxDepthReached REAL DEFAULT 0.0, ' +
      'Outcome TEXT NOT NULL);';
    FQuerySync.ExecSQL;

    FQuerySync.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS Extracted_Anomalies (' +
      'SampleID INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'MissionID INTEGER NOT NULL, ' +
      'DepthFound REAL NOT NULL, ' +
      'AnomalyType TEXT NOT NULL, ' +
      'IntegrityAtExtraction REAL NOT NULL);';
    FQuerySync.ExecSQL;

    FQuerySync.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS ROV_Specs (' +
      'ID INTEGER PRIMARY KEY CHECK (ID = 1), ' +
      'ResearchPoints INTEGER DEFAULT 0, ' +
      'HullLevel INTEGER DEFAULT 1, ' +
      'BatteryLevel INTEGER DEFAULT 1, ' +
      'ThrusterLevel INTEGER DEFAULT 1, ' +
      'DecoyLevel INTEGER DEFAULT 0, ' +
      'EMPLevel INTEGER DEFAULT 0);';
    FQuerySync.ExecSQL;

    FQuerySync.SQL.Text := 'INSERT OR IGNORE INTO ROV_Specs (ID, ResearchPoints, HullLevel, BatteryLevel, ThrusterLevel, DecoyLevel, EMPLevel) VALUES (1, 0, 1, 1, 1, 0, 0)';
    FQuerySync.ExecSQL;

    FTransSync.Commit;
  except
    if FTransSync.Active then FTransSync.Rollback;
  end;
end;

constructor TDatabaseManager.Create(const DBPath: String);
begin
  inherited Create;

  FConnSync := TSQLite3Connection.Create(nil);
  FConnSync.DatabaseName := DBPath;
  FTransSync := TSQLTransaction.Create(nil);
  FTransSync.DataBase := FConnSync;
  FConnSync.Transaction := FTransSync;

  FQuerySync := TSQLQuery.Create(nil);
  FQuerySync.DataBase := FConnSync;

  FConnSync.Connected := True;

  // Pastikan tidak ada transaksi aktif sebelum mengubah pragma WAL
  if FTransSync.Active then FTransSync.Commit;

  try
    FConnSync.ExecuteDirect('PRAGMA journal_mode = WAL;');
    FConnSync.ExecuteDirect('PRAGMA busy_timeout = 5000;');
  except
    // Abaikan jika mode WAL gagal diterapkan karena batasan hak akses file
  end;

  InitializeDatabase;

  FWorker := TDBWorkerThread.Create(DBPath);
end;

destructor TDatabaseManager.Destroy;
begin
  FWorker.Free;
  FQuerySync.Free;
  FTransSync.Free;
  FConnSync.Free;
  inherited Destroy;
end;

function TDatabaseManager.StartNewMission: Integer;
begin
  Result := -1;
  try
    if not FConnSync.Connected then FConnSync.Connected := True;

    if FTransSync.Active then FTransSync.Commit;

    FTransSync.StartTransaction;
    FQuerySync.SQL.Text := 'INSERT INTO Missions (Outcome) VALUES (''IN_PROGRESS'')';
    FQuerySync.ExecSQL;

    FQuerySync.SQL.Text := 'SELECT last_insert_rowid() AS LastID';
    FQuerySync.Open;
    if not FQuerySync.EOF then
      Result := FQuerySync.FieldByName('LastID').AsInteger;
    FQuerySync.Close;

    FTransSync.Commit;
  except
    if FTransSync.Active then FTransSync.Rollback;
  end;
end;

procedure TDatabaseManager.EndMission(MissionID: Integer; MaxDepth: Single; const Outcome: String);
var
  Task: TDBTask;
begin
  Task.Action := dbaLogMissionEnd;
  Task.MissionID := MissionID;
  Task.Depth := MaxDepth;
  Task.TextData := Outcome;
  Task.Integrity := 0.0;
  FWorker.EnqueueTask(Task);
end;

procedure TDatabaseManager.LogAnomaly(MissionID: Integer; DepthFound: Single; const AnomalyType: String; Integrity: Single);
var
  Task: TDBTask;
begin
  Task.Action := dbaLogAnomaly;
  Task.MissionID := MissionID;
  Task.Depth := DepthFound;
  Task.TextData := AnomalyType;
  Task.Integrity := Integrity;
  FWorker.EnqueueTask(Task);
end;

procedure TDatabaseManager.AddResearchPointsAsync(Points: Integer);
var
  Task: TDBTask;
begin
  if Points <= 0 then Exit;
  Task.Action := dbaAddPoints;
  Task.MissionID := Points;
  FWorker.EnqueueTask(Task);
end;

function TDatabaseManager.GetROVSpecs: TROVSpecs;
begin
  Result.ResearchPoints := 0;
  Result.HullLevel := 1;
  Result.BatteryLevel := 1;
  Result.ThrusterLevel := 1;
  Result.DecoyLevel := 0;
  Result.EMPLevel := 0;

  try
    if not FConnSync.Connected then FConnSync.Connected := True;

    if FTransSync.Active then FTransSync.Commit;

    FQuerySync.SQL.Text := 'SELECT ResearchPoints, HullLevel, BatteryLevel, ThrusterLevel, DecoyLevel, EMPLevel FROM ROV_Specs WHERE ID = 1';
    FQuerySync.Open;
    if not FQuerySync.EOF then
    begin
      Result.ResearchPoints := FQuerySync.FieldByName('ResearchPoints').AsInteger;
      Result.HullLevel := FQuerySync.FieldByName('HullLevel').AsInteger;
      Result.BatteryLevel := FQuerySync.FieldByName('BatteryLevel').AsInteger;
      Result.ThrusterLevel := FQuerySync.FieldByName('ThrusterLevel').AsInteger;
      Result.DecoyLevel := FQuerySync.FieldByName('DecoyLevel').AsInteger;
      Result.EMPLevel := FQuerySync.FieldByName('EMPLevel').AsInteger;
    end;
    FQuerySync.Close;

    if FTransSync.Active then FTransSync.Commit;
  except
    if FTransSync.Active then FTransSync.Rollback;
  end;
end;

procedure TDatabaseManager.SaveROVSpecs(const Specs: TROVSpecs);
begin
  try
    if not FConnSync.Connected then FConnSync.Connected := True;

    if FTransSync.Active then FTransSync.Commit;

    FTransSync.StartTransaction;
    FQuerySync.SQL.Text := 'UPDATE ROV_Specs SET ResearchPoints = :RP, HullLevel = :HL, BatteryLevel = :BL, ThrusterLevel = :TL, DecoyLevel = :DL, EMPLevel = :EL WHERE ID = 1';
    FQuerySync.Params.ParamByName('RP').AsInteger := Specs.ResearchPoints;
    FQuerySync.Params.ParamByName('HL').AsInteger := Specs.HullLevel;
    FQuerySync.Params.ParamByName('BL').AsInteger := Specs.BatteryLevel;
    FQuerySync.Params.ParamByName('TL').AsInteger := Specs.ThrusterLevel;
    FQuerySync.Params.ParamByName('DL').AsInteger := Specs.DecoyLevel;
    FQuerySync.Params.ParamByName('EL').AsInteger := Specs.EMPLevel;
    FQuerySync.ExecSQL;
    FTransSync.Commit;
  except
    if FTransSync.Active then FTransSync.Rollback;
  end;
end;

end.
