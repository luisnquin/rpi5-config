{
  lib,
  stdenv,
  zig,
}:
stdenv.mkDerivation {
  pname = "skinner";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./build.zig ./src];
  };
  nativeBuildInputs = [zig.hook];
  doCheck = true;
  meta.mainProgram = "skinner";
}
