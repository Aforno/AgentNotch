cask "agents-notch" do
  version "0.1.1"
  sha256 "72cc1624a84f2d3b80971200a5d343571597c06cc2a0e3fb752a9417caf82199"

  url "https://github.com/Aforno/AgentNotch/releases/download/v#{version}/Agents-Notch-#{version}-macOS-arm64.zip"
  name "Agents Notch"
  desc "Notch status surface for local coding agents"
  homepage "https://github.com/Aforno/AgentNotch"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+)$/i)
    strategy :github_releases do |json, regex|
      json.map do |release|
        next if release["draft"]

        match = release["tag_name"]&.match(regex)
        next if match.blank?

        match[1]
      end
    end
  end

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Agents Notch.app"

  zap trash: [
    "~/.agentsnotch",
    "~/Library/Application Support/AgentsNotch",
    "~/Library/Preferences/com.afonsoferreira.AgentsNotch.plist",
  ]

  caveats <<~EOS
    Preview releases may be ad-hoc signed. macOS Gatekeeper can block the first
    launch. If that happens, Control-click the app, choose Open, and confirm.
  EOS
end
