{
  description = "Zedha — a personal-first downstream distribution of Zed";

  inputs = {
    zed.url = "github:zed-industries/zed";
    nixpkgs.follows = "zed/nixpkgs";
  };

  outputs = { nixpkgs, zed, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      stable = builtins.fromJSON (builtins.readFile ./upstream/stable.json);
      zedha = pkgs.callPackage ./nix/zedha.nix {
        inherit stable;
        zedPackage = zed.packages.${system}.default;
      };
    in {
      packages.${system} = { inherit zedha; default = zedha; };
      checks.${system}.package-identity = pkgs.callPackage ./nix/check-package.nix { inherit zedha; };
    };

  nixConfig = {
    extra-substituters = [ "https://zed.cachix.org" "https://zedha.cachix.org" ];
    extra-trusted-public-keys = [
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
      "zedha.cachix.org-1:UpjUzPJxtCvofuoE2vsEJ5u5LLXfi4o78ADvfF7bEWg="
    ];
  };
}
