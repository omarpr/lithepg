# Homebrew cask template for LithePG releases. The production release helper
# publishes a signed and notarized artifact. The separate preview helper adds a
# visible unsigned-build warning to the copy published in the external tap.

cask "lithepg" do
  version "1.0.11"
  sha256 "cf9302a3d1c0b474b48598d0f39c541ed0bf4461bfba487477bcf755a0b9c63a"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG-#{version}.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://www.lithepg.app/"

  depends_on macos: :sonoma

  app "LithePG.app"

  uninstall quit: "dev.omarpr.lithepg"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
