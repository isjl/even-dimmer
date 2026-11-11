# Homebrew cask for Even Dimmer. scripts/release.sh updates `version` and `sha256`.
# It lives in the tap repo github.com/isjl/homebrew-tap as Casks/even-dimmer.rb, so
# people can install with:
#   brew install --cask isjl/tap/even-dimmer
cask "even-dimmer" do
  version "1.0.0"
  sha256 "071ddf5b84594bc522cfa51b2d4a5e612f650a3978dc216815a4633543ea63bd"

  url "https://github.com/isjl/even-dimmer/releases/download/v#{version}/EvenDimmer-#{version}.zip"
  name "Even Dimmer"
  desc "Dim the MacBook screen and keyboard light below Apple's lowest setting"
  homepage "https://github.com/isjl/even-dimmer"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself with Sparkle.
  auto_updates true
  depends_on macos: :ventura

  app "Even Dimmer.app"

  # The app isn't notarized, so remove the download quarantine flag; otherwise macOS
  # refuses to open it. Only do this for apps you trust.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Even Dimmer.app"],
        writable_paths: ["Even Dimmer.app"],
        writable_base:  :appdir
  end

  uninstall quit: "io.github.evendimmer"

  zap trash: "~/Library/Preferences/io.github.evendimmer.plist"
end
