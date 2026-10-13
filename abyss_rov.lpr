program abyss_rov;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces,
  Forms,
  uMainForm, UnitAbout, BASS;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title:='Abyss_ROV';
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.CreateForm(TFormAbout, FormAbout);
  Application.Run;
end.

