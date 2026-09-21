shell tick

# Navigation script for Pre-APE project
# Usage: ./nav.sh <frontend|backend|both|test> [action]

cd /DATA/AppData/pre_ape

case "$1" in
    frontend)
        cd frontend
        echo "Opened frontend directory"
        echo "Flutter commands available:"
        echo "  - flutter pub get"
        echo "  - flutter run"
        echo "  - flutter build apk/ios/web"
        echo "  - flutter analyze"
        ;;
        
    backend)
        cd frontend/backend
        echo "Opened backend directory"
        echo "Python commands available:"
        echo "  - python main.py (run server)"
        echo "  - python -m pytest tests/ (run tests)"
        echo "  - pip install -r requirements.txt (install dependencies)"
        ;;
        
    both)
        echo "=== FRONTEND ==="
        cd frontend
        echo "Frontend: /DATA/AppData/pre_ape/frontend"
        echo ""
        echo "=== BACKEND ==="
        cd backend
        echo "Backend: /DATA/AppData/pre_ape/frontend/backend"
        echo ""
        ;;
        
    test)
        echo "=== FLUTTER TESTS ==="
        cd frontend
        flutter test
        echo ""
        echo "=== PYTHON TESTS ==="
        cd backend
        python -m pytest tests/ -v
        ;;
        
    run-frontend)
        cd frontend
        flutter run --verbose
        ;;
        
    run-backend)
        cd backend
        python main.py
        ;;
        
    status)
        echo "=== PRE-APE PROJECT STATUS ==="
        echo ""
        echo "Frontend: /DATA/AppData/pre_ape/frontend"
        echo "$(find frontend -name "*.dart" | wc -l) Dart files"
        echo "$(find frontend -name "*.yaml" -o -name "*.yml" | wc -l) YAML files"
        echo ""
        echo "Backend: /DATA/AppData/pre_ape/frontend/backend"
        echo "$(find backend -name "*.py" | wc -l) Python files"
        echo "$(find backend -name "requirements.txt" | wc -l) requirements files"
        echo ""
        echo "Total API endpoints: ~20"
        echo "Core features: ✅ Energy gauge ✅ AR measurement ✅ AI vision ✅ Google OAuth"
        echo ""
        ;;
        
    *)
        echo "Usage: ./nav.sh <frontend|backend|both|test|run-frontend|run-backend|status>"
        echo ""
        echo "Quick commands:"
        echo "  ./nav.sh status           - Show project status"
        echo "  ./nav.sh both             - Navigate to both dirs"
        echo "  ./nav.sh run-backend      - Start Python FastAPI server"
        echo "  ./nav.sh run-frontend     - Start Flutter app"
        echo "  ./nav.sh test             - Run tests for both"
        ;;
esac