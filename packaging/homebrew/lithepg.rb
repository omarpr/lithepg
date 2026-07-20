# Homebrew cask template for LithePG releases. The production release helper
# publishes a signed and notarized artifact. The separate preview helper adds a
# visible unsigned-build warning to the copy published in the external tap.

cask "lithepg" do
  version "1.0.2-preview.1"
  sha256 "17460e9c9e62b76ffed65a39c7cd72bd27d4fdc84adcaa80769844782e3c5d77"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
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
