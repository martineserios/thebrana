#!/bin/bash
# Wrapper: ensures ruflo MCP server reads ~/.swarm/memory.db (1006 entries)
# instead of .swarm/ relative to whatever CWD CC launches from.
cd /home/martineserios
exec /home/martineserios/.nvm/versions/node/v20.19.0/bin/ruflo "$@"
