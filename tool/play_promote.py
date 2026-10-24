#!/usr/bin/env python3
"""Promotes a build to a Google Play track, with its release notes, from the first of the given
tracks that has it.

Used by .github/workflows/promote.yml. Reads the service account's key from
PLAY_SERVICE_ACCOUNT_JSON, and takes the package, the track to promote to, the tracks to look for
the build on (in order, comma-separated) and the build (version code):

    play_promote.py dev.jumpingfox.chameleon production beta,alpha 8

Does nothing if the track already has that build. Needs google-auth and requests.
"""

import json
import os
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"


def main(package: str, to_track: str, from_tracks: str, build: str) -> None:
    credentials = service_account.Credentials.from_service_account_info(
        json.loads(os.environ["PLAY_SERVICE_ACCOUNT_JSON"]),
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    session = AuthorizedSession(credentials)
    edits = f"{API}/{package}/edits"

    def call(method: str, url: str, **kwargs) -> dict:
        response = session.request(method, url, **kwargs)
        if not response.ok:
            sys.exit(f"{method} {url} → {response.status_code}: {response.text}")
        return response.json() if response.content else {}

    # Changes are made in an "edit", and only take effect when it's committed.
    edit = call("POST", edits)["id"]

    def releases(track: str) -> list[dict]:
        return call("GET", f"{edits}/{edit}/tracks/{track}").get("releases", [])

    def discard() -> None:
        session.delete(f"{edits}/{edit}")

    if any(build in r.get("versionCodes", []) for r in releases(to_track)):
        print(f"Build {build} is already on {to_track}.")
        discard()
        return

    found = next(
        ((track, r) for track in from_tracks.split(",") for r in releases(track) if build in r.get("versionCodes", [])),
        None,
    )
    if found is None:
        discard()
        sys.exit(f"Build {build} isn't on {from_tracks}, so there's nothing to promote.")
    from_track, release = found

    call(
        "PUT",
        f"{edits}/{edit}/tracks/{to_track}",
        json={
            "track": to_track,
            "releases": [
                {
                    "name": release.get("name", build),
                    "versionCodes": [build],
                    "status": "completed",  # to everyone on the track, once Google's review passes
                    "releaseNotes": release.get("releaseNotes", []),
                }
            ],
        },
    )
    call("POST", f"{edits}/{edit}:commit")
    print(f"Promoted build {build} ({release.get('name', '')}) from {from_track} to {to_track}.")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
