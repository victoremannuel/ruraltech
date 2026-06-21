#include <cassert>
#include <fstream>
#include <sstream>
#include <string>

int main() {
  std::ifstream sourceFile("coleira/coleira.ino");
  assert(sourceFile.good());

  std::ostringstream sourceBuffer;
  sourceBuffer << sourceFile.rdbuf();
  const std::string source = sourceBuffer.str();

  const size_t functionStart =
      source.find("static void applyDownlink(const LoRaFrame& frame) {");
  const size_t functionEnd =
      source.find("\nstatic ", functionStart + 1);
  assert(functionStart != std::string::npos);
  assert(functionEnd != std::string::npos);

  const std::string functionBody =
      source.substr(functionStart, functionEnd - functionStart);
  const size_t routeCheck = functionBody.find("if (rpv2Fence) {");
  const size_t routeLog =
      functionBody.find("RPV2_BINARY_DOWNLINK_ROUTE", routeCheck);
  const size_t bindingCheck =
      functionBody.find("if (!bindingReady_)", routeCheck);
  const size_t scopeCheck =
      functionBody.find("frame.scopeId != bindingScopeIdValue()", routeCheck);
  const size_t rpv2Apply =
      functionBody.find("applyFenceRpv2Frame(frame);", routeCheck);
  const size_t metadataExtraction =
      functionBody.find("extractCommandMetadataFromPayload(");
  const size_t jsonParsing = functionBody.find("deserializeJson(");
  const size_t legacyAuditLog =
      functionBody.find("AS_COLLAR_RX_FENCE_COMMAND(");

  assert(routeCheck != std::string::npos);
  assert(routeLog != std::string::npos);
  assert(bindingCheck != std::string::npos);
  assert(scopeCheck != std::string::npos);
  assert(rpv2Apply != std::string::npos);
  assert(metadataExtraction != std::string::npos);
  assert(jsonParsing != std::string::npos);
  assert(legacyAuditLog != std::string::npos);
  assert(routeCheck < metadataExtraction);
  assert(bindingCheck < rpv2Apply);
  assert(scopeCheck < rpv2Apply);
  assert(rpv2Apply < metadataExtraction);
  assert(rpv2Apply < jsonParsing);
  assert(rpv2Apply < legacyAuditLog);
  assert(functionBody.find("PolygonAuditContext auditCtx{};") !=
         std::string::npos);
  return 0;
}
