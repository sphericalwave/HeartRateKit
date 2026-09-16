//
//  ReExports.swift
//  HeartRateKit
//
//  `import HeartRateKit` keeps exposing everything HeartRateCore defines
//  (HeartRateSource, HeartRateSample, MockHeartRateSource, ...) so existing
//  consumers don't need a second import after the package split.
//

@_exported import HeartRateCore
