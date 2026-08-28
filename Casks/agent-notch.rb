cask "agent-notch" do
  version "0.2.0"
  sha256 "1f764315c44c477186612e0f81e81ecdd7329caa2d5e16d32658c93d8d815ee6"

  url "https://github.com/Aforno/AgentNotch/releases/download/v#{version}/Agent-Notch-#{version}-macOS-arm64.zip"
  name "Agent Notch"
  desc "Notch status surface for local coding agents"
  homepage "https://github.com/Aforno/AgentNotch"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Agent Notch.app"

  zap trash: [
    "~/.agentnotch",
    "~/Library/Application Support/AgentNotch",
    "~/Library/Preferences/com.afonsoferreira.AgentNotch.plist",
  ]

  caveats <<~EOS
    Preview releases may be ad-hoc signed. macOS Gatekeeper can block the first
    launch. If that happens, Control-click the app, choose Open, and confirm.
  EOS
end
