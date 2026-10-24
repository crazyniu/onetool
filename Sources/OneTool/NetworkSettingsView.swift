// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct NetworkSettingsPage: View {
    @Bindable var network: NetworkSettings
    @State private var address = ""
    var body: some View {
        ToolSection(title: L("Current Connection")) {
            HStack {
                if let current = network.current {
                    Text(current.name).fontWeight(.medium)
                    Spacer()
                    Button(L("Refresh"), systemImage: "arrow.clockwise") { network.refresh() }
                } else { HelpText(L("No active network connection.")) }
            }
            if let current = network.current {
                LabeledContent(L("Router"), value: current.router.isEmpty ? "—" : current.router)
                LabeledContent("DNS", value: current.dns.isEmpty ? L("Automatic") : current.dns.joined(separator: ", "))
            }
        }.disabled(network.isChanging)
        ToolSection(title: L("Saved Addresses")) {
            ForEach(network.profiles) { profile in
                HStack(spacing: 12) {
                    Button { Task { await network.requestSwitch(profile) } } label: {
                        HStack {
                            Image(systemName: network.isActive(profile) ? "checkmark.circle.fill" : "circle")
                            Text(profile.address).monospacedDigit()
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(network.isActive(profile) || network.current?.canSwitch != true)
                        .accessibilityLabel(profile.address)
                        .accessibilityValue(network.isActive(profile) ? L("Active") : L("Saved"))
                    Button { network.remove(profile.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help(L("Delete")).accessibilityLabel(LF("Delete %@", profile.address))
                }
                if profile.id != network.profiles.last?.id { Divider() }
            }
            if network.profiles.isEmpty { HelpText(L("Add the router addresses you want to switch between.")) }
            HStack {
                TextField("192.168.1.1", text: $address).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L("DNS & Router Address")).onSubmit { addAddress() }
                Button(L("Add"), systemImage: "plus") { addAddress() }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HelpText(L("Click an IP address to use it for both the current connection’s gateway and DNS."))
        }.disabled(network.isChanging)
        HStack {
            if network.isChanging { ProgressView().controlSize(.small); Text(L("Updating network settings…")) }
            Spacer()
            if network.canRestore {
                Button(L("Restore Previous Configuration")) { Task { await network.restore() } }.disabled(network.isChanging)
            }
        }
        ErrorText(error: network.error)
        if let notice = network.notice { Text(notice).font(.callout).textSelection(.enabled) }
        Color.clear.frame(height: 0)
            .alert(L("Use Manual IPv4?"), isPresented: Binding(get: { network.pendingDHCP != nil }, set: { _ in })) {
                Button(L("Switch")) { Task { await network.confirmDHCP() } }
                Button(L("Cancel"), role: .cancel) { network.cancelDHCP() }
            } message: {
                Text(L("Switching keeps the current IP address and subnet mask, and changes IPv4 from DHCP to Manual. Reserve this IP on your router to avoid address conflicts."))
            }
            .onAppear { network.refresh() }
    }
    private func addAddress() {
        if network.save(.init(address: address)) { address = "" }
    }
}
