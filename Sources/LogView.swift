import SwiftUI
import UIKit

// MARK: - Log model

final class LogModel: ObservableObject {
    @Published var text = ""

    func append(_ msg: String) {
        if msg.hasSuffix("\n") {
            text += msg
        } else {
            text += msg + "\n"
        }
    }

    func clear() {
        text = ""
    }

    func exportToDocuments(fileName: String = "EnsWilde-Log.txt") throws -> URL {
        let url = URL.documentsDirectory.appendingPathComponent(fileName)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Globals

let logPipe = Pipe()
let GLOBAL_LOG = LogModel()

// MARK: - Log view

struct LogView: View {
    @StateObject private var log = GLOBAL_LOG
    @State private var ran = false

    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(GLOBAL_LOG.text)
                    .font(.system(size: 12).monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Spacer().id(0)
            }
            .onAppear {
                guard !ran else { return }
                ran = true

                logPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    guard !data.isEmpty, var logString = String(data: data, encoding: .utf8) else { return }

                    DispatchQueue.main.async {
                        if !Utils.udid.isEmpty, logString.contains(Utils.udid) {
                            logString = logString.replacingOccurrences(of: Utils.udid, with: "<redacted>")
                        }

                        log.append(logString)
                        proxy.scrollTo(0)
                    }
                }
            }
        }
        .navigationTitle(L("log_output_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(L("log_clear")) {
                    GLOBAL_LOG.clear()
                }

                Button(L("log_export_txt")) {
                    do {
                        let url = try GLOBAL_LOG.exportToDocuments()
                        exportURL = url
                        exportError = nil
                        showShareSheet = true
                    } catch {
                        exportError = "\(error)"
                    }
                }
            }
        }
        .alert(L("log_export_failed"), isPresented: Binding(
            get: { exportError != nil },
            set: { _ in exportError = nil }
        )) {
            Button(L("alert_ok")) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            } else {
                Text(L("log_no_file"))
                    .padding()
            }
        }
    }

    init() {
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        dup2(logPipe.fileHandleForWriting.fileDescriptor, fileno(stdout))
        dup2(logPipe.fileHandleForWriting.fileDescriptor, fileno(stderr))
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}