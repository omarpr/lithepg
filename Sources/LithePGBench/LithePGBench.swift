import Foundation
import LithePGCore

@main
struct LithePGBench {
    static func main() async {
        do {
            let args = try Args.parse(CommandLine.arguments)
            let report = try await run(args: args)
            if args.json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                print()
            } else {
                print("query: \(report.query)")
                print("iterations: \(report.iterations), warmup: \(report.warmup)")
                print(String(format: "median: %.3f ms", report.medianMs))
                print(String(format: "p95: %.3f ms", report.p95Ms))
                print(String(format: "min/max: %.3f / %.3f ms", report.minMs, report.maxMs))
            }
        } catch Args.ParseError.help(let message) {
            print(message)
            exit(0)
        } catch Args.ParseError.usage(let message) {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("error: \(ErrorRedaction.redactCredentials(in: error))\n".utf8))
            exit(1)
        }
    }

    private static func run(args: Args) async throws -> BenchReport {
        let connector = PostgresConnector()
        do {
            let config = try ConnectionConfig(url: args.url)
            try await connector.open(config: config)
            for _ in 0..<args.warmup {
                _ = try await connector.execute(args.query)
            }

            var samples: [Double] = []
            samples.reserveCapacity(args.iterations)
            for _ in 0..<args.iterations {
                let start = ContinuousClock.now
                _ = try await connector.execute(args.query)
                samples.append(milliseconds(since: start))
            }
            try await connector.shutdown()

            return BenchReport(
                urlLabel: label(for: config),
                query: args.query,
                warmup: args.warmup,
                iterations: args.iterations,
                samplesMs: samples,
                medianMs: percentile(samples, 0.50),
                p95Ms: percentile(samples, 0.95),
                minMs: samples.min() ?? 0,
                maxMs: samples.max() ?? 0
            )
        } catch {
            try? await connector.shutdown()
            throw error
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: ContinuousClock.now)
        return milliseconds(elapsed)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rawIndex = Int(ceil(percentile * Double(sorted.count))) - 1
        let index = min(max(rawIndex, 0), sorted.count - 1)
        return sorted[index]
    }

    private static func label(for config: ConnectionConfig) -> String {
        "\(config.username)@\(config.host):\(config.port)/\(config.database)"
    }
}

struct BenchReport: Codable, Equatable {
    let urlLabel: String
    let query: String
    let warmup: Int
    let iterations: Int
    let samplesMs: [Double]
    let medianMs: Double
    let p95Ms: Double
    let minMs: Double
    let maxMs: Double
}

struct Args {
    let url: String
    let query: String
    let iterations: Int
    let warmup: Int
    let json: Bool

    enum ParseError: Error {
        case usage(String)
        case help(String)
    }

    static func parse(_ argv: [String]) throws -> Args {
        var url: String?
        var query = "SELECT 1 AS lithepg_v04_bench"
        var iterations = 30
        var warmup = 5
        var json = false

        var i = 1
        while i < argv.count {
            switch argv[i] {
            case "--url":
                guard i + 1 < argv.count else { throw ParseError.usage("--url needs a value") }
                url = argv[i + 1]
                i += 2
            case "--query":
                guard i + 1 < argv.count else { throw ParseError.usage("--query needs a value") }
                query = argv[i + 1]
                i += 2
            case "--iterations":
                guard i + 1 < argv.count, let value = Int(argv[i + 1]), value > 0 else {
                    throw ParseError.usage("--iterations needs a positive integer")
                }
                iterations = value
                i += 2
            case "--warmup":
                guard i + 1 < argv.count, let value = Int(argv[i + 1]), value >= 0 else {
                    throw ParseError.usage("--warmup needs a non-negative integer")
                }
                warmup = value
                i += 2
            case "--json":
                json = true
                i += 1
            case "--help", "-h":
                throw ParseError.help("usage: lithepg-bench --url <postgres://...> [--query SQL] [--warmup N] [--iterations N] [--json]")
            default:
                throw ParseError.usage("unknown argument: \(argv[i])")
            }
        }

        guard let url, !url.isEmpty else { throw ParseError.usage("--url is required") }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.usage("--query cannot be empty")
        }
        return Args(url: url, query: query, iterations: iterations, warmup: warmup, json: json)
    }
}
