#!/usr/bin/env python3
import json
import math
import re
from collections import Counter
from pathlib import Path

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.export import to_html, to_json
from graphify.report import generate


ROOT = Path(__file__).resolve().parents[1]
PY_DETECTS = {
    "app": Path("/tmp/app.detect.json"),
    "brain": Path("/tmp/brain.detect.json"),
    "coleira": Path("/tmp/coleira.detect.json"),
    "gateway-matriz": Path("/tmp/gwm.detect.json"),
    "gateway": Path("/tmp/gateway.detect.json"),
}


def edge(source, target, relation, source_file, confidence="EXTRACTED", confidence_score=1.0):
    return {
        "source": source,
        "target": target,
        "relation": relation,
        "confidence": confidence,
        "confidence_score": confidence_score,
        "source_file": source_file,
        "source_location": None,
        "weight": 1.0,
    }


SEMANTIC = {
    "app": {
        "nodes": [
            {
                "id": "app_mobile_management_platform",
                "label": "Plataforma Móvel de Gestão Rural",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_supabase_backend",
                "label": "Backend Supabase",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_gateway_ws_bridge",
                "label": "Bridge WebSocket com Gateway",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_operational_map",
                "label": "Mapa Operacional",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_auth_access_control",
                "label": "Autenticação e Controle de Acesso",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_device_onboarding",
                "label": "Onboarding de Dispositivos",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_geofence_command_flow",
                "label": "Fluxo de Publicação de Geofence",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_herding_command_flow",
                "label": "Fluxo de Plano de Condução",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_event_audit_feed",
                "label": "Feed de Eventos e Auditoria",
                "file_type": "document",
                "source_file": "funcionamento.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "app_flutterflow_mvp",
                "label": "Esqueleto MVP no FlutterFlow",
                "file_type": "document",
                "source_file": "flutterflow_notes.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
        ],
        "edges": [
            edge("app_mobile_management_platform", "lib_main_dart", "references", "README.md"),
            edge("app_mobile_management_platform", "app_supabase_backend", "conceptually_related_to", "README.md", "INFERRED", 0.92),
            edge("app_mobile_management_platform", "app_gateway_ws_bridge", "conceptually_related_to", "funcionamento.md", "INFERRED", 0.9),
            edge("app_mobile_management_platform", "app_operational_map", "conceptually_related_to", "funcionamento.md", "INFERRED", 0.88),
            edge("app_auth_access_control", "services_auth_service_dart", "references", "funcionamento.md"),
            edge("app_supabase_backend", "services_cloud_service_dart", "references", "README.md"),
            edge("app_gateway_ws_bridge", "services_gateway_service_dart", "references", "funcionamento.md"),
            edge("app_device_onboarding", "services_bluetooth_discovery_service_dart", "references", "funcionamento.md"),
            edge("app_operational_map", "screens_home_shell_dart", "references", "funcionamento.md"),
            edge("app_operational_map", "lib_widgets_polygon_editing_map_dart", "references", "funcionamento.md"),
            edge("app_geofence_command_flow", "lib_screens_geofence_screen_dart", "references", "funcionamento.md"),
            edge("app_herding_command_flow", "lib_screens_herding_screen_dart", "references", "funcionamento.md"),
            edge("app_event_audit_feed", "lib_screens_events_screen_dart", "references", "funcionamento.md"),
            edge("app_event_audit_feed", "package_ruraltech_app_screens_device_details_screen_dart", "references", "funcionamento.md"),
            edge("app_operational_map", "app_geofence_command_flow", "conceptually_related_to", "funcionamento.md", "INFERRED", 0.86),
            edge("app_operational_map", "app_herding_command_flow", "conceptually_related_to", "funcionamento.md", "INFERRED", 0.84),
            edge("app_flutterflow_mvp", "app_mobile_management_platform", "rationale_for", "flutterflow_notes.md", "INFERRED", 0.78),
        ],
    },
    "brain": {
        "nodes": [
            {
                "id": "brain_ruraltech_scope",
                "label": "Escopo do Projeto RuralTech",
                "file_type": "document",
                "source_file": "projetos/ruraltech.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "brain_system_overview",
                "label": "Visão Geral da Arquitetura",
                "file_type": "document",
                "source_file": "arquitetura/visao-geral.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "brain_end_to_end_flows",
                "label": "Fluxos Ponta a Ponta",
                "file_type": "document",
                "source_file": "arquitetura/fluxos-comunicacao-ponta-a-ponta.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "brain_technology_stack",
                "label": "Stack Tecnológico do Monorepo",
                "file_type": "document",
                "source_file": "arquitetura/stack-tecnologico.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "brain_supabase_data_model",
                "label": "Modelo de Dados Supabase",
                "file_type": "document",
                "source_file": "arquitetura/modelagem-dados-supabase.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "brain_gradual_supabase_migration",
                "label": "Migração Gradual Firebase para Supabase",
                "file_type": "document",
                "source_file": "decisoes/migracao-supabase.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "brain_design_handoff",
                "label": "Handoff de Redesign V2",
                "file_type": "document",
                "source_file": "tarefas/design_handoff_ruraltech_v2.1/README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
        ],
        "edges": [
            edge("brain_ruraltech_scope", "brain_system_overview", "references", "projetos/ruraltech.md"),
            edge("brain_ruraltech_scope", "brain_end_to_end_flows", "references", "projetos/ruraltech.md"),
            edge("brain_ruraltech_scope", "brain_technology_stack", "references", "projetos/ruraltech.md"),
            edge("brain_system_overview", "brain_end_to_end_flows", "conceptually_related_to", "arquitetura/visao-geral.md", "INFERRED", 0.93),
            edge("brain_system_overview", "brain_technology_stack", "conceptually_related_to", "arquitetura/visao-geral.md", "INFERRED", 0.86),
            edge("brain_end_to_end_flows", "brain_supabase_data_model", "conceptually_related_to", "arquitetura/fluxos-comunicacao-ponta-a-ponta.md", "INFERRED", 0.88),
            edge("brain_gradual_supabase_migration", "brain_supabase_data_model", "rationale_for", "decisoes/migracao-supabase.md", "INFERRED", 0.9),
            edge("brain_gradual_supabase_migration", "brain_technology_stack", "conceptually_related_to", "decisoes/migracao-supabase.md", "INFERRED", 0.83),
            edge("brain_design_handoff", "brain_ruraltech_scope", "conceptually_related_to", "tarefas/design_handoff_ruraltech_v2.1/README.md", "INFERRED", 0.77),
        ],
    },
    "coleira": {
        "nodes": [
            {
                "id": "coleira_autonomous_collar_firmware",
                "label": "Firmware Autônomo da Coleira",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "coleira_local_geofence",
                "label": "Aplicação Local de Geofence",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "coleira_herding_execution",
                "label": "Execução Local de Herding",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "coleira_animal_safety",
                "label": "Segurança Animal no Firmware",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "coleira_lora_protocol",
                "label": "Protocolo LoRa da Coleira",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
        ],
        "edges": [
            edge("coleira_autonomous_collar_firmware", "loramanager_cpp", "references", "README.md"),
            edge("coleira_autonomous_collar_firmware", "sensorsmanager_cpp", "references", "README.md"),
            edge("coleira_autonomous_collar_firmware", "smartgps_cpp", "references", "README.md"),
            edge("coleira_local_geofence", "geofence_cpp", "references", "README.md"),
            edge("coleira_herding_execution", "herdingcontroller_cpp", "references", "README.md"),
            edge("coleira_animal_safety", "safetycontroller_cpp", "references", "README.md"),
            edge("coleira_lora_protocol", "loraprotocol_cpp", "references", "README.md"),
            edge("coleira_lora_protocol", "cryptoengine_cpp", "references", "README.md"),
            edge("coleira_local_geofence", "coleira_herding_execution", "conceptually_related_to", "README.md", "INFERRED", 0.78),
            edge("coleira_animal_safety", "coleira_local_geofence", "rationale_for", "README.md", "INFERRED", 0.74),
        ],
    },
    "gateway-matriz": {
        "nodes": [
            {
                "id": "gwm_central_property_node",
                "label": "Nó Central da Propriedade",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gwm_cloud_queue_backhaul",
                "label": "Backhaul de Fila Cloud",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gwm_lora_dispatch",
                "label": "Despacho LoRa Fragmentado",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gwm_local_api_surface",
                "label": "Superfície HTTP e WebSocket Local",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gwm_audit_logging",
                "label": "Log Auditável em SD",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
        ],
        "edges": [
            edge("gwm_central_property_node", "loragateway_cpp", "references", "README.md"),
            edge("gwm_cloud_queue_backhaul", "queuestreamsupport_cpp", "references", "README.md"),
            edge("gwm_local_api_surface", "apiserver_cpp", "references", "README.md"),
            edge("gwm_audit_logging", "sdlogger_cpp", "references", "README.md"),
            edge("gwm_lora_dispatch", "loraprotocol_cpp", "references", "README.md"),
            edge("gwm_lora_dispatch", "cryptoengine_cpp", "references", "README.md"),
            edge("gwm_cloud_queue_backhaul", "gwm_lora_dispatch", "conceptually_related_to", "README.md", "INFERRED", 0.89),
            edge("gwm_local_api_surface", "gwm_cloud_queue_backhaul", "conceptually_related_to", "README.md", "INFERRED", 0.77),
        ],
    },
    "gateway": {
        "nodes": [
            {
                "id": "gateway_local_bridge",
                "label": "Gateway Local de Campo",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gateway_rest_ws_surface",
                "label": "Superfície REST e WebSocket",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gateway_lora_fragmentation",
                "label": "Fragmentação de Comandos LoRa",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gateway_sd_audit_log",
                "label": "Log em SD com Hash Chain",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
            {
                "id": "gateway_multihop_relay",
                "label": "Relay LoRa Multi-hop",
                "file_type": "document",
                "source_file": "README.md",
                "source_location": None,
                "source_url": None,
                "captured_at": None,
                "author": None,
                "contributor": None,
            },
        ],
        "edges": [
            edge("gateway_local_bridge", "loragateway_cpp", "references", "README.md"),
            edge("gateway_rest_ws_surface", "apiserver_cpp", "references", "README.md"),
            edge("gateway_lora_fragmentation", "loraprotocol_cpp", "references", "README.md"),
            edge("gateway_lora_fragmentation", "cryptoengine_cpp", "references", "README.md"),
            edge("gateway_sd_audit_log", "sdlogger_cpp", "references", "README.md"),
            edge("gateway_multihop_relay", "blepresence_cpp", "conceptually_related_to", "README.md", "INFERRED", 0.61),
            edge("gateway_rest_ws_surface", "gateway_lora_fragmentation", "conceptually_related_to", "README.md", "INFERRED", 0.78),
        ],
    },
}


STOP = {
    "dart",
    "cpp",
    "h",
    "md",
    "json",
    "yaml",
    "swift",
    "ino",
    "screen",
    "service",
    "manager",
    "controller",
    "test",
    "package",
    "users",
    "victoremannuel",
    "ruraltech",
    "lib",
    "app",
    "brain",
    "coleira",
    "gateway",
    "matriz",
    "readme",
}


def normalize_token(token):
    token = token.lower()
    token = re.sub(r"[^a-z0-9]+", "", token)
    return token


def pick_label(labels):
    counter = Counter()
    for label in labels:
        parts = re.split(r"[^A-Za-z0-9]+", label)
        for raw in parts:
            token = normalize_token(raw)
            if len(token) < 4 or token in STOP or token.isdigit():
                continue
            counter[token] += 1
    if not counter:
        return "Core Cluster"
    top = [word for word, _ in counter.most_common(3)]
    return " ".join(word.capitalize() for word in top[:2])


def build_area(area):
    area_dir = ROOT / area
    out_dir = area_dir / "graphify-out"
    ast_path = out_dir / ".graphify_ast.json"
    detect_path = PY_DETECTS[area]
    detect = json.loads(detect_path.read_text())
    ast = json.loads(ast_path.read_text())
    sem = SEMANTIC[area]

    seen = {n["id"] for n in ast["nodes"]}
    merged_nodes = list(ast["nodes"])
    for node in sem["nodes"]:
        if node["id"] not in seen:
            merged_nodes.append(node)
            seen.add(node["id"])

    extraction = {
        "nodes": merged_nodes,
        "edges": ast["edges"] + sem["edges"],
        "hyperedges": sem.get("hyperedges", []),
        "input_tokens": 0,
        "output_tokens": 0,
    }
    (out_dir / ".graphify_extract.json").write_text(json.dumps(extraction, indent=2))

    G = build_from_json(extraction)
    communities = cluster(G)
    cohesion = score_all(G, communities)
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)

    labels = {}
    for cid, node_ids in communities.items():
        labels[cid] = pick_label([G.nodes[nid].get("label", nid) for nid in node_ids[:80]])

    questions = suggest_questions(G, communities, labels)
    report = generate(
        G,
        communities,
        cohesion,
        labels,
        gods,
        surprises,
        detect,
        {"input": 0, "output": 0},
        str(area_dir.resolve()),
        suggested_questions=questions,
    )

    (out_dir / "GRAPH_REPORT.md").write_text(report)
    to_json(G, communities, str(out_dir / "graph.json"))
    if G.number_of_nodes() <= 5000:
        to_html(G, communities, str(out_dir / "graph.html"), community_labels=labels)

    summary = {
        "area": area,
        "nodes": G.number_of_nodes(),
        "edges": G.number_of_edges(),
        "communities": len(communities),
        "labels": labels,
        "god_nodes": gods[:5],
        "questions": questions[:5],
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False))


def main():
    for area in ["app", "brain", "coleira", "gateway-matriz", "gateway"]:
        build_area(area)
        print(f"built {area}")


if __name__ == "__main__":
    main()
