{ ... }:

{
  source = ../examples/hello.ks;
  expected_output = builtins.toFile "expected_output" ''
    Hello
    World
  '';
}