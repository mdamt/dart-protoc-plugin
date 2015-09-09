// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library protoc.benchmark.suite;

import "benchmark.dart";
import "benchmarks/int32_json.dart";
import "benchmarks/repeated_int32_json.dart";
import 'generated/benchmark.pb.dart' as pb;

/// Runs a benchmark suite, returning progress until done.
///
/// [samplesPerBatch] is the number of times a benchmark will be run
/// before going on to the next one. They will be executed round-robin
/// until they're all done.
Iterable<pb.Report> runSuite(pb.Suite suite, {samplesPerBatch: 1}) sync* {

  // Create a blank report with one response per request.
  var report = new pb.Report()
    ..status = pb.Status.RUNNING;
  for (var request in suite.requests) {
    var r = new pb.Response()..request = request;
    report.responses.add(r);
  }

  // Set up progress reports.
  int sampleCount = 0;
  int totalSamples = 0;
  for (var request in suite.requests) {
    totalSamples += request.samples;
  }
  pb.Report progress() {
    report.message = "Running ($sampleCount/$totalSamples)";
    return report.clone();
  }

  // Send first progress message before starting.
  yield progress();

  var benchmarks = <Benchmark>[];
  for (var r in report.responses) {
    benchmarks.add(createBenchmark(r.request));
  }

  // Collect the requested number of samples.
  while (sampleCount < totalSamples) {
    for (var i = 0; i < benchmarks.length; i++) {
      var b = benchmarks[i];
      var r = report.responses[i];
      int batchSize = r.request.samples - r.samples.length;
      if (batchSize == 0) continue;
      if (batchSize > samplesPerBatch) batchSize = samplesPerBatch;
      for (pb.Sample s in b.measure(r.request, batchSize)) {
        r.samples.add(s);
        sampleCount++;
        yield progress();
      }
    }
  }

  // Send final report.
  report.status = pb.Status.DONE;
  report.message = "Done";
  yield report;
}

/// Creates the appropriate Benchmark instance for a protobuf.
Benchmark createBenchmark(pb.Request r) {
  var type = allBenchmarks[r.id];
  if (type == null) {
    throw new ArgumentError("unknown benchmark: ${r.id.name}");
  }
  return type.create(r);
}

final Map<pb.BenchmarkID, BenchmarkType> allBenchmarks =
    _makeTypeMap([Int32Benchmark.$type, RepeatedInt32Benchmark.$type]);

Map<pb.BenchmarkID, BenchmarkType> _makeTypeMap(List<BenchmarkType> types) {
  var out = <pb.BenchmarkID, BenchmarkType>{};
  for (var type in types) {
    if (out.containsKey(type.id)) {
      throw "already added: $type.id.name";
    }
    out[type.id] = type;
  }
  return new Map.unmodifiable(out);
}