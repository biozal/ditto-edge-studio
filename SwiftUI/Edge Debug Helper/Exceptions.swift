//
//  Exceptions.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/18/25.
//
import Foundation

struct ConnectionException: Error {
    let message: String
}

struct InvalidCredentialsException: Error {
    let message: String
}

struct ApplicationUserIsNil: Error {
    let message: String
}

struct InvalidEndpointUrl: Error {
    let message: String
}

struct InvalidStateError: Error {
    let message: String
}

struct InvalidStoreState: Error {
    let message: String
}

struct NotImplemented: Error {
    let message: String
}
