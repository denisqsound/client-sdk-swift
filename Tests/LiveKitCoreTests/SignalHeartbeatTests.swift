/*
 * Copyright 2026 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
@testable import LiveKit
import Testing

@Suite(.serialized)
struct SignalHeartbeatTests {
    @Test func missingPongAfterEachResumeDisconnectsSignaling() async throws {
        let client = SignalClient()
        let state = await client._state
        let joinResponse = Livekit_JoinResponse.with {
            $0.pingInterval = 1
            $0.pingTimeout = 1
        }
        state.mutate { $0.lastJoinResponse = joinResponse }

        // Сервер задаёт heartbeat только в JoinResponse, не в ReconnectResponse.
        // Очередь отправки оставлена приостановленной: pong не приходит.
        for attempt in 1 ... 2 {
            await client.cleanUp(withError: LiveKitError(.network))
            state.mutate {
                $0.connectionState = .connected
                $0.disconnectError = nil
            }
            await client._restartPingTimer()

            let deadline = Date().addingTimeInterval(5)
            while state.connectionState == .connected, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(state.connectionState == .disconnected, "После resume \(attempt) потеря pong должна обнаруживаться")
            #expect(state.disconnectError?.type == .serverPingTimedOut)
        }
        await client.cleanUp()
    }

    @Test func finalCleanupDoesNotApplyHeartbeatToNextSession() async throws {
        let client = SignalClient()
        let state = await client._state
        let joinResponse = Livekit_JoinResponse.with {
            $0.pingInterval = 1
            $0.pingTimeout = 1
        }
        state.mutate { $0.lastJoinResponse = joinResponse }
        await client.cleanUp(resetSession: true)

        // Следующая сессия ещё не получила собственный JoinResponse.
        state.mutate { $0.connectionState = .connected }
        await client._restartPingTimer()
        try await Task.sleep(nanoseconds: 3_000_000_000)

        #expect(state.connectionState == .connected)
        #expect(state.disconnectError == nil)
        await client.cleanUp(resetSession: true)
    }
}
