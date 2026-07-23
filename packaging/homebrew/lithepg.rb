# Homebrew cask template for LithePG releases. The production release helper
# publishes a signed and notarized artifact. The separate preview helper adds a
# visible unsigned-build warning to the copy published in the external tap.

cask "lithepg" do
  version "1.0.4-preview.1"
  sha256 "319e7f4ee9cb81d00cb40e10c7d9cb553c3972092a58dd1a39515c763a17c3e2"

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
