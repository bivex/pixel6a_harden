#!/usr/bin/env python3
"""
Staff-Grade Configuration Parser for pixel_setup.
Supports standard PyYAML with robust built-in fallback parser.
Provides safe environment generation, key lookups, and JSON exports without `eval`.
"""
import sys
import os
import json

def load_yaml(filepath):
    if not os.path.exists(filepath):
        print(f"[ERROR] Config file not found at: {filepath}", file=sys.stderr)
        sys.exit(1)
        
    try:
        import yaml
        with open(filepath, "r", encoding="utf-8") as f:
            return yaml.safe_load(f)
    except ImportError:
        pass

    config = {}
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("---"):
                continue
            if ":" in line:
                key, val = line.split(":", 1)
                key = key.strip()
                val = val.split("#")[0].strip()
                val = val.strip('"\'')
                if val.lower() == "true":
                    val = True
                elif val.lower() == "false":
                    val = False
                elif val.isdigit():
                    val = int(val)
                config[key] = val
    return config

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(script_dir, ".."))
    config_path = os.path.join(project_root, "config", "default_settings.yml")
    
    config = load_yaml(config_path)

    if len(sys.argv) > 1:
        flag = sys.argv[1]
        if flag == "--json":
            print(json.dumps(config, indent=2))
        elif flag == "--env":
            for k, v in config.items():
                if isinstance(v, bool):
                    v_str = "1" if v else "0"
                else:
                    v_str = str(v)
                print(f'CFG_{k.upper()}="{v_str}"')
        else:
            target_key = flag
            if target_key in config:
                val = config[target_key]
                print("1" if val is True else "0" if val is False else str(val))
            else:
                print(f"[ERROR] Key '{target_key}' not found in configuration.", file=sys.stderr)
                sys.exit(1)
    else:
        for k, v in config.items():
            if isinstance(v, bool):
                v_str = "1" if v else "0"
            else:
                v_str = str(v)
            print(f'CFG_{k.upper()}="{v_str}"')

if __name__ == "__main__":
    main()
