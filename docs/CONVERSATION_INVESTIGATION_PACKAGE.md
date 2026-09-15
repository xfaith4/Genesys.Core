# Conversation Investigation Package

This package is produced from a single Genesys Cloud conversation ID. It writes an investigation run first, then exports a shareable evidence package.

## Live command

```powershell
Import-Module ./modules/Genesys.Ops/Genesys.Ops.psd1 -Force
Connect-GenesysCloud -AccessToken $env:GENESYS_BEARER_TOKEN -Region 'usw2.pure.cloud'

$run = Get-GenesysConversationInvestigation `
  -ConversationId '<conversation-guid>' `
  -OutputRoot './out'

Export-GenesysConversationInvestigationPackage `
  -RunFolder $run.RunFolder `
  -OutputDirectory './out/conversation-package' `
  -Force
```

`-SipTracePath` is not required for live use. The exporter queries Genesys Cloud for SIP metadata and requests the PCAP download itself.

## API sequence

1. `GET /api/v2/conversations/{conversationId}`
   - Reads the conversation `startTime` and `endTime`.
   - These values are required because `POST /api/v2/analytics/conversations/details/query` requires an `interval`.
2. `POST /api/v2/analytics/conversations/details/query`
   - Uses `interval = <startTime>/<endTime>`.
   - Uses a conversation filter for the target conversation ID.
3. `GET /api/v2/telephony/siptraces`
   - Uses `conversationId`, `dateStart`, and `dateEnd`.
   - Produces SIP metadata rows for the timeline and CSV evidence.
4. `POST /api/v2/telephony/siptraces/download`
   - Requests the matching PCAP package.
5. `GET /api/v2/telephony/siptraces/download/{downloadId}`
   - Polls for the signed PCAP URL, then downloads the `.pcap` file.

## Output files

- `<package>.html`
- `<package>.timeline.csv`
- `<package>.sip-trace.csv`
- `<package>.pcap-metadata.csv`
- `<package>.findings.csv`
- `<package>.xlsx`
- `<package>.pcap`
- `<package>.package.json`

## Permissions

The SIP/PCAP path requires Genesys Cloud telephony PCAP permissions:

- `telephony:pcap:view`
- `telephony:pcap:add`

If the package is generated from an existing run folder without a connected Genesys session, the exporter records a warning in the package JSON and skips the PCAP download. Use `-SipTracePath` only for offline/manual packaging.
