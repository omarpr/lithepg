# Draft Homebrew cask template for the LithePG main repository.
#
# Do not publish this file to an external Homebrew tap until Omar approves the
# tap target. Replace the version and sha256 placeholders with values from the
# final signed/notarized GitHub Release artifact before running tap checks.

cask "lithepg" do
  version "REPLACE_WITH_VERSION"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/omarpr/lithepg/releases/download/v#{version}/LithePG.app.zip",
      verified: "github.com/omarpr/lithepg/"
  name "LithePG"
  desc "Lean PostgreSQL client with local-first AI"
  homepage "https://github.com/omarpr/lithepg"

  depends_on macos: ">= :sonoma"

  app "LithePG.app"

  uninstall quit: "dev.omarpr.lithepg"

  zap trash: [
    "~/Library/Application Support/LithePG",
    "~/Library/Preferences/dev.omarpr.lithepg.plist",
  ]
end
