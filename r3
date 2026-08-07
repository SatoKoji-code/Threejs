<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1.0"
  >
  <title>ReCap メッシュタイルビューアー</title>

  <style>
    * {
      box-sizing: border-box;
    }

    html,
    body {
      width: 100%;
      height: 100%;
      margin: 0;
      overflow: hidden;
      background: #d9dde3;
      font-family:
        -apple-system,
        BlinkMacSystemFont,
        "Segoe UI",
        "Yu Gothic UI",
        "Meiryo",
        sans-serif;
    }

    #viewer {
      position: fixed;
      inset: 0;
    }

    #viewer canvas {
      display: block;
      width: 100%;
      height: 100%;
    }

    #statusPanel {
      position: fixed;
      top: 16px;
      left: 16px;
      z-index: 10;
      width: min(430px, calc(100vw - 32px));
      padding: 14px 16px;
      color: #ffffff;
      background: rgba(20, 20, 20, 0.84);
      border-radius: 8px;
      line-height: 1.5;
      box-shadow: 0 3px 16px rgba(0, 0, 0, 0.28);
      pointer-events: none;
    }

    #statusTitle {
      margin-bottom: 6px;
      font-size: 16px;
      font-weight: 700;
    }

    #statusMessage {
      font-size: 14px;
      word-break: break-all;
    }

    #progressArea {
      margin-top: 10px;
    }

    #progressBackground {
      width: 100%;
      height: 8px;
      overflow: hidden;
      background: rgba(255, 255, 255, 0.2);
      border-radius: 4px;
    }

    #progressBar {
      width: 0%;
      height: 100%;
      background: #58a6ff;
      border-radius: 4px;
      transition: width 0.2s ease;
    }

    #progressText {
      margin-top: 5px;
      font-size: 12px;
      color: #dddddd;
    }

    #errorPanel {
      display: none;
      position: fixed;
      left: 16px;
      right: 16px;
      bottom: 16px;
      z-index: 20;
      max-height: 35vh;
      padding: 14px 16px;
      overflow: auto;
      color: #ffffff;
      background: rgba(160, 25, 25, 0.92);
      border-radius: 8px;
      font-size: 13px;
      line-height: 1.5;
      white-space: pre-wrap;
    }

    #operationGuide {
      position: fixed;
      right: 16px;
      bottom: 16px;
      z-index: 10;
      padding: 10px 12px;
      color: #ffffff;
      background: rgba(20, 20, 20, 0.72);
      border-radius: 6px;
      font-size: 12px;
      line-height: 1.6;
      pointer-events: none;
    }

    @media (max-width: 600px) {
      #operationGuide {
        display: none;
      }

      #statusPanel {
        top: 8px;
        left: 8px;
        width: calc(100vw - 16px);
      }

      #errorPanel {
        left: 8px;
        right: 8px;
        bottom: 8px;
      }
    }
  </style>

  <script type="importmap">
    {
      "imports": {
        "three": "https://cdn.jsdelivr.net/npm/three@0.180.0/build/three.module.js",
        "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.180.0/examples/jsm/"
      }
    }
  </script>
</head>

<body>
  <div id="viewer"></div>

  <div id="statusPanel">
    <div id="statusTitle">
      ReCap メッシュタイルビューアー
    </div>

    <div id="statusMessage">
      初期化しています。
    </div>

    <div id="progressArea">
      <div id="progressBackground">
        <div id="progressBar"></div>
      </div>

      <div id="progressText">
        読み込み準備中
      </div>
    </div>
  </div>

  <div id="errorPanel"></div>

  <div id="operationGuide">
    左ドラッグ：回転<br>
    右ドラッグ：移動<br>
    ホイール：拡大・縮小
  </div>

  <script type="module">
    import * as THREE from "three";

    import {
      OrbitControls
    } from "three/addons/controls/OrbitControls.js";

    import {
      GLTFLoader
    } from "three/addons/loaders/GLTFLoader.js";

    import {
      MeshoptDecoder
    } from "three/addons/libs/meshopt_decoder.module.js";


    // ============================================================
    // 運営側の設定
    // 原則として、データ切替時はこのフォルダパスだけ変更します。
    // 最後に「/」を付けてください。
    // ============================================================

    const TILE_FOLDER_PATH = "./models/buildingA/";


    // ============================================================
    // タイルファイル名の設定
    // ============================================================

    const TILE_FILE_PREFIX = "タイル";
    const TILE_FILE_EXTENSION = ".glb";

    /*
      誤動作防止用の最大タイル番号です。
      実際のタイル数が1000を超える場合は増やしてください。
    */
    const MAX_TILE_COUNT = 1000;

    /*
      true:
      最初に存在しない番号が見つかった時点で終了します。

      false:
      欠番があっても確認を続け、
      連続欠番数が上限に達した時点で終了します。
    */
    const STOP_AT_FIRST_MISSING_TILE = true;
    const MAX_CONSECUTIVE_MISSING_TILES = 5;


    // ============================================================
    // 座標軸設定
    // ============================================================

    /*
      ReCapに合わせてZ軸を高さ方向として扱います。
    */
    const USE_Z_UP_COORDINATES = true;

    /*
      GLB自体が横倒しの場合のみ角度を変更してください。

      通常:
      X = 0
      Y = 0
      Z = 0

      例:
      X方向に-90度回転する場合
      MODEL_ROTATION_X_DEGREES = -90
    */
    const MODEL_ROTATION_X_DEGREES = 0;
    const MODEL_ROTATION_Y_DEGREES = 0;
    const MODEL_ROTATION_Z_DEGREES = 0;


    // ============================================================
    // 表示設定
    // ============================================================

    const BACKGROUND_COLOR = 0xd9dde3;

    const SHOW_GRID = true;
    const SHOW_AXES = false;

    /*
      モデルを明るく見せるための設定です。
    */
    const AMBIENT_LIGHT_INTENSITY = 2.8;
    const HEMISPHERE_LIGHT_INTENSITY = 2.2;
    const MAIN_LIGHT_INTENSITY = 3.4;
    const FILL_LIGHT_INTENSITY = 2.0;
    const FRONT_LIGHT_INTENSITY = 1.8;
    const CAMERA_LIGHT_INTENSITY = 1.5;

    /*
      影は完全に無効化します。
    */
    const ENABLE_SHADOWS = false;


    // ============================================================
    // Three.jsで使用する変数
    // ============================================================

    let scene;
    let camera;
    let renderer;
    let controls;
    let gltfLoader;

    let cameraLight;
    let animationFrameId = null;

    const loadedTileGroup = new THREE.Group();
    loadedTileGroup.name = "LoadedReCapTiles";

    const loadedTiles = [];

    let loadedTileCount = 0;
    let failedTileCount = 0;


    // ============================================================
    // HTML要素
    // ============================================================

    const viewerElement =
      document.getElementById("viewer");

    const statusMessage =
      document.getElementById("statusMessage");

    const progressBar =
      document.getElementById("progressBar");

    const progressText =
      document.getElementById("progressText");

    const errorPanel =
      document.getElementById("errorPanel");


    // ============================================================
    // 初期化
    // ============================================================

    async function init() {
      try {
        updateStatus(
          "Three.jsを初期化しています。",
          "読み込み準備中",
          0
        );

        createScene();
        createCamera();
        createRenderer();
        createControls();
        createLights();
        createHelpers();
        createLoader();
        configureLoadedTileGroup();
        registerEvents();

        scene.add(loadedTileGroup);

        startAnimation();

        await loadAllTiles();

      } catch (error) {
        console.error(
          "初期化中にエラーが発生しました。",
          error
        );

        showError(
          "ビューアーの初期化に失敗しました。",
          error
        );
      }
    }


    // ============================================================
    // シーン作成
    // ============================================================

    function createScene() {
      if (USE_Z_UP_COORDINATES) {
        THREE.Object3D.DEFAULT_UP.set(0, 0, 1);
      } else {
        THREE.Object3D.DEFAULT_UP.set(0, 1, 0);
      }

      scene = new THREE.Scene();
      scene.background = new THREE.Color(BACKGROUND_COLOR);

      if (USE_Z_UP_COORDINATES) {
        scene.up.set(0, 0, 1);
      } else {
        scene.up.set(0, 1, 0);
      }
    }


    // ============================================================
    // カメラ作成
    // ============================================================

    function createCamera() {
      const aspect =
        window.innerWidth / window.innerHeight;

      camera = new THREE.PerspectiveCamera(
        50,
        aspect,
        0.01,
        100000000
      );

      if (USE_Z_UP_COORDINATES) {
        camera.up.set(0, 0, 1);
        camera.position.set(10, -10, 10);
      } else {
        camera.up.set(0, 1, 0);
        camera.position.set(10, 10, 10);
      }
    }


    // ============================================================
    // レンダラー作成
    // ============================================================

    function createRenderer() {
      renderer = new THREE.WebGLRenderer({
        antialias: true,
        alpha: false,
        powerPreference: "high-performance"
      });

      renderer.setSize(
        window.innerWidth,
        window.innerHeight
      );

      renderer.setPixelRatio(
        Math.min(
          window.devicePixelRatio,
          2
        )
      );

      renderer.outputColorSpace =
        THREE.SRGBColorSpace;

      renderer.toneMapping =
        THREE.ACESFilmicToneMapping;

      /*
        モデルが暗い場合に全体を明るくします。
        明るすぎる場合は1.1～1.3程度へ下げてください。
      */
      renderer.toneMappingExposure = 1.45;

      /*
        影を完全に無効化します。
      */
      renderer.shadowMap.enabled = ENABLE_SHADOWS;

      viewerElement.appendChild(
        renderer.domElement
      );
    }


    // ============================================================
    // マウス操作設定
    // ============================================================

    function createControls() {
      controls = new OrbitControls(
        camera,
        renderer.domElement
      );

      controls.enableDamping = true;
      controls.dampingFactor = 0.08;

      controls.enableRotate = true;
      controls.enablePan = true;
      controls.enableZoom = true;

      controls.screenSpacePanning = true;

      controls.minDistance = 0.01;
      controls.maxDistance = Infinity;

      controls.target.set(0, 0, 0);
      controls.update();
    }


    // ============================================================
    // ライト作成
    // ============================================================

    function createLights() {
      /*
        シーン全体を均一に明るくします。
      */
      const ambientLight =
        new THREE.AmbientLight(
          0xffffff,
          AMBIENT_LIGHT_INTENSITY
        );

      ambientLight.castShadow = false;
      scene.add(ambientLight);


      /*
        空と地面側から柔らかく照らします。
      */
      const hemisphereLight =
        new THREE.HemisphereLight(
          0xffffff,
          0x8a8a8a,
          HEMISPHERE_LIGHT_INTENSITY
        );

      if (USE_Z_UP_COORDINATES) {
        hemisphereLight.position.set(0, 0, 1000);
      } else {
        hemisphereLight.position.set(0, 1000, 0);
      }

      hemisphereLight.castShadow = false;
      scene.add(hemisphereLight);


      /*
        主照明
      */
      const mainLight =
        new THREE.DirectionalLight(
          0xffffff,
          MAIN_LIGHT_INTENSITY
        );

      mainLight.position.set(
        500,
        -500,
        800
      );

      mainLight.castShadow = false;
      scene.add(mainLight);


      /*
        反対側からの補助照明
      */
      const fillLight =
        new THREE.DirectionalLight(
          0xffffff,
          FILL_LIGHT_INTENSITY
        );

      fillLight.position.set(
        -500,
        500,
        400
      );

      fillLight.castShadow = false;
      scene.add(fillLight);


      /*
        正面側からの照明
      */
      const frontLight =
        new THREE.DirectionalLight(
          0xffffff,
          FRONT_LIGHT_INTENSITY
        );

      frontLight.position.set(
        0,
        -800,
        250
      );

      frontLight.castShadow = false;
      scene.add(frontLight);


      /*
        カメラと一緒に移動する照明です。
        視点側から常にモデルを照らします。
      */
      cameraLight =
        new THREE.PointLight(
          0xffffff,
          CAMERA_LIGHT_INTENSITY,
          0,
          0
        );

      cameraLight.castShadow = false;
      scene.add(cameraLight);
    }


    // ============================================================
    // 補助表示
    // ============================================================

    function createHelpers() {
      if (SHOW_GRID) {
        const gridHelper =
          new THREE.GridHelper(
            1000,
            100,
            0x888888,
            0xaaaaaa
          );

        gridHelper.name = "GridHelper";

        /*
          GridHelperは標準でXZ平面です。
          Z-upではXY平面へ回転します。
        */
        if (USE_Z_UP_COORDINATES) {
          gridHelper.rotation.x = Math.PI / 2;
        }

        scene.add(gridHelper);
      }

      if (SHOW_AXES) {
        const axesHelper =
          new THREE.AxesHelper(100);

        axesHelper.name = "AxesHelper";
        scene.add(axesHelper);
      }
    }


    // ============================================================
    // GLBローダー作成
    // ============================================================

    function createLoader() {
      gltfLoader = new GLTFLoader();

      gltfLoader.setMeshoptDecoder(
        MeshoptDecoder
      );
    }


    // ============================================================
    // 読み込みグループの座標軸補正
    // ============================================================

    function configureLoadedTileGroup() {
      loadedTileGroup.rotation.set(
        THREE.MathUtils.degToRad(
          MODEL_ROTATION_X_DEGREES
        ),
        THREE.MathUtils.degToRad(
          MODEL_ROTATION_Y_DEGREES
        ),
        THREE.MathUtils.degToRad(
          MODEL_ROTATION_Z_DEGREES
        )
      );
    }


    // ============================================================
    // イベント登録
    // ============================================================

    function registerEvents() {
      window.addEventListener(
        "resize",
        onWindowResize
      );

      window.addEventListener(
        "beforeunload",
        disposeViewer
      );

      renderer.domElement.addEventListener(
        "webglcontextlost",
        onWebGLContextLost,
        false
      );

      renderer.domElement.addEventListener(
        "webglcontextrestored",
        onWebGLContextRestored,
        false
      );
    }


    // ============================================================
    // 全タイル読み込み
    // ============================================================

    async function loadAllTiles() {
      loadedTileCount = 0;
      failedTileCount = 0;

      let consecutiveMissingCount = 0;
      let lastAttemptedTileNumber = 0;

      updateStatus(
        "タイルファイルを検索しています。",
        "タイル1から順番に確認します。",
        0
      );

      for (
        let tileNumber = 1;
        tileNumber <= MAX_TILE_COUNT;
        tileNumber++
      ) {
        lastAttemptedTileNumber = tileNumber;

        const fileName =
          buildTileFileName(tileNumber);

        const filePath =
          buildTileFilePath(tileNumber);

        updateStatus(
          `${fileName}を確認しています。`,
          `読み込み済み：${loadedTileCount}個`,
          calculateSearchProgress(tileNumber)
        );

        try {
          const gltf =
            await loadSingleTile(
              filePath,
              fileName,
              tileNumber
            );

          consecutiveMissingCount = 0;
          loadedTileCount++;

          addLoadedTileToScene(
            gltf,
            fileName,
            filePath,
            tileNumber
          );

          await waitForNextFrame();

        } catch (error) {
          const isMissingFile =
            isLikelyMissingFileError(error);

          if (isMissingFile) {
            consecutiveMissingCount++;

            console.warn(
              `ファイルが見つかりません：${filePath}`
            );

            if (STOP_AT_FIRST_MISSING_TILE) {
              break;
            }

            if (
              consecutiveMissingCount >=
              MAX_CONSECUTIVE_MISSING_TILES
            ) {
              break;
            }

            continue;
          }

          failedTileCount++;

          console.error(
            `読み込みに失敗しました：${filePath}`,
            error
          );

          appendError(
            `${fileName}の読み込みに失敗しました。`,
            error
          );
        }
      }

      finishTileLoading(
        lastAttemptedTileNumber
      );
    }


    // ============================================================
    // タイルファイル名・パス作成
    // ============================================================

    function buildTileFileName(tileNumber) {
      return (
        TILE_FILE_PREFIX +
        tileNumber +
        TILE_FILE_EXTENSION
      );
    }


    function buildTileFilePath(tileNumber) {
      const normalizedFolderPath =
        TILE_FOLDER_PATH.endsWith("/")
          ? TILE_FOLDER_PATH
          : TILE_FOLDER_PATH + "/";

      return (
        normalizedFolderPath +
        buildTileFileName(tileNumber)
      );
    }


    // ============================================================
    // タイル1個の読み込み
    // ============================================================

    function loadSingleTile(
      filePath,
      fileName,
      tileNumber
    ) {
      return new Promise(
        (resolve, reject) => {
          gltfLoader.load(
            filePath,

            function onLoad(gltf) {
              progressBar.style.width = "100%";
              progressText.textContent =
                `${fileName}の読み込み完了`;

              resolve(gltf);
            },

            function onProgress(event) {
              updateTileProgress(
                event,
                fileName,
                tileNumber
              );
            },

            function onError(error) {
              reject(error);
            }
          );
        }
      );
    }


    // ============================================================
    // タイル読み込み進捗
    // ============================================================

    function updateTileProgress(
      event,
      fileName,
      tileNumber
    ) {
      if (
        event &&
        event.lengthComputable &&
        event.total > 0
      ) {
        const percent =
          Math.min(
            100,
            event.loaded / event.total * 100
          );

        progressBar.style.width =
          `${percent.toFixed(1)}%`;

        progressText.textContent =
          `${fileName}：` +
          `${formatBytes(event.loaded)} / ` +
          `${formatBytes(event.total)} ` +
          `(${percent.toFixed(1)}%)`;

        return;
      }

      if (
        event &&
        typeof event.loaded === "number"
      ) {
        progressBar.style.width = "15%";

        progressText.textContent =
          `${fileName}：` +
          `${formatBytes(event.loaded)}を受信中`;

        return;
      }

      progressBar.style.width = "5%";
      progressText.textContent =
        `${fileName}を読み込み中`;
    }


    // ============================================================
    // 読み込んだタイルをシーンへ追加
    // ============================================================

    function addLoadedTileToScene(
      gltf,
      fileName,
      filePath,
      tileNumber
    ) {
      const tileScene = gltf.scene;

      tileScene.name = fileName;

      tileScene.userData.tileNumber =
        tileNumber;

      tileScene.userData.fileName =
        fileName;

      tileScene.userData.filePath =
        filePath;

      tileScene.traverse(
        function configureObject(object) {
          if (!object.isMesh) {
            return;
          }

          /*
            モデルの影を完全に無効化します。
          */
          object.castShadow = false;
          object.receiveShadow = false;

          object.frustumCulled = true;

          if (object.geometry) {
            if (!object.geometry.boundingBox) {
              object.geometry.computeBoundingBox();
            }

            if (!object.geometry.boundingSphere) {
              object.geometry.computeBoundingSphere();
            }
          }

          const materials =
            Array.isArray(object.material)
              ? object.material
              : [object.material];

          for (const material of materials) {
            if (!material) {
              continue;
            }

            if (material.map) {
              material.map.colorSpace =
                THREE.SRGBColorSpace;

              material.map.needsUpdate = true;
            }

            /*
              黒くつぶれにくくするため、
              環境光の影響を少し強めます。
            */
            if (
              "envMapIntensity" in material
            ) {
              material.envMapIntensity = 1.4;
            }

            material.needsUpdate = true;
          }
        }
      );

      loadedTileGroup.add(tileScene);

      loadedTiles.push({
        tileNumber,
        fileName,
        filePath,
        scene: tileScene,
        gltf
      });

      console.log(
        `読み込み完了：${fileName}`
      );
    }


    // ============================================================
    // 全タイル読み込み完了時
    // ============================================================

    function finishTileLoading(
      lastAttemptedTileNumber
    ) {
      if (loadedTileCount === 0) {
        updateStatus(
          "タイルデータを読み込めませんでした。",
          "フォルダパスとファイル名を確認してください。",
          0
        );

        showError(
          "タイルデータが見つかりませんでした。",
          new Error(
            [
              `確認したパス：${TILE_FOLDER_PATH}`,
              `想定ファイル名：${buildTileFileName(1)}`,
              "",
              "確認事項：",
              "・TILE_FOLDER_PATHが正しいか",
              "・タイル番号が1から始まっているか",
              "・拡張子が.glbか",
              "・Webサーバーからindex.htmlを開いているか"
            ].join("\n")
          )
        );

        return;
      }

      fitCameraToLoadedModels();

      const completionMessage =
        failedTileCount > 0
          ? `読み込み完了：${loadedTileCount}個、` +
            `失敗：${failedTileCount}個`
          : `読み込み完了：${loadedTileCount}個`;

      updateStatus(
        completionMessage,
        `最後に確認した番号：${lastAttemptedTileNumber}`,
        100
      );

      progressText.textContent =
        `合計${loadedTileCount}個のタイルを表示しています。`;
    }


    // ============================================================
    // 読み込んだモデル全体へカメラを合わせる
    // ============================================================

    function fitCameraToLoadedModels() {
      const boundingBox =
        new THREE.Box3().setFromObject(
          loadedTileGroup
        );

      if (boundingBox.isEmpty()) {
        console.warn(
          "モデルの範囲を取得できませんでした。"
        );

        return;
      }

      const center =
        boundingBox.getCenter(
          new THREE.Vector3()
        );

      const size =
        boundingBox.getSize(
          new THREE.Vector3()
        );

      const maxDimension =
        Math.max(
          size.x,
          size.y,
          size.z
        );

      if (
        !Number.isFinite(maxDimension) ||
        maxDimension <= 0
      ) {
        return;
      }

      const verticalFov =
        THREE.MathUtils.degToRad(
          camera.fov
        );

      let cameraDistance =
        maxDimension /
        (
          2 *
          Math.tan(verticalFov / 2)
        );

      cameraDistance *= 1.4;

      const direction =
        USE_Z_UP_COORDINATES
          ? new THREE.Vector3(
              1,
              -1,
              0.65
            ).normalize()
          : new THREE.Vector3(
              1,
              0.65,
              1
            ).normalize();

      camera.position.copy(
        center.clone().add(
          direction.multiplyScalar(
            cameraDistance
          )
        )
      );

      camera.near =
        Math.max(
          cameraDistance / 10000,
          0.001
        );

      camera.far =
        Math.max(
          cameraDistance * 100,
          maxDimension * 100
        );

      camera.updateProjectionMatrix();

      controls.target.copy(center);

      controls.minDistance =
        Math.max(
          maxDimension * 0.0001,
          0.001
        );

      controls.maxDistance =
        Math.max(
          maxDimension * 100,
          cameraDistance * 10
        );

      controls.update();

      if (cameraLight) {
        cameraLight.position.copy(
          camera.position
        );
      }
    }


    // ============================================================
    // ステータス表示
    // ============================================================

    function updateStatus(
      message,
      detail,
      percent
    ) {
      statusMessage.textContent =
        message;

      progressText.textContent =
        detail;

      const safePercent =
        Math.max(
          0,
          Math.min(
            100,
            Number(percent) || 0
          )
        );

      progressBar.style.width =
        `${safePercent}%`;
    }


    function calculateSearchProgress(
      currentTileNumber
    ) {
      const estimatedPercent =
        currentTileNumber /
        Math.max(
          currentTileNumber + 5,
          10
        ) *
        90;

      return Math.min(
        90,
        estimatedPercent
      );
    }


    // ============================================================
    // ファイルなしエラー判定
    // ============================================================

    function isLikelyMissingFileError(
      error
    ) {
      if (!error) {
        return true;
      }

      const message =
        String(
          error.message ||
          error.statusText ||
          error
        ).toLowerCase();

      const missingKeywords = [
        "404",
        "not found",
        "failed to fetch",
        "networkerror",
        "network error",
        "load failed"
      ];

      return missingKeywords.some(
        function includesKeyword(keyword) {
          return message.includes(keyword);
        }
      );
    }


    // ============================================================
    // エラー表示
    // ============================================================

    function showError(
      title,
      error
    ) {
      errorPanel.style.display =
        "block";

      errorPanel.textContent =
        `${title}\n\n${getErrorDetail(error)}`;
    }


    function appendError(
      title,
      error
    ) {
      errorPanel.style.display =
        "block";

      const newMessage =
        `${title}\n${getErrorDetail(error)}`;

      if (
        errorPanel.textContent.trim()
      ) {
        errorPanel.textContent +=
          `\n\n------------------------------\n\n${newMessage}`;
      } else {
        errorPanel.textContent =
          newMessage;
      }
    }


    function getErrorDetail(error) {
      if (!error) {
        return "詳細情報はありません。";
      }

      if (error instanceof Error) {
        return (
          error.stack ||
          error.message ||
          String(error)
        );
      }

      return String(error);
    }


    // ============================================================
    // ウィンドウサイズ変更
    // ============================================================

    function onWindowResize() {
      if (
        !camera ||
        !renderer
      ) {
        return;
      }

      camera.aspect =
        window.innerWidth /
        window.innerHeight;

      camera.updateProjectionMatrix();

      renderer.setSize(
        window.innerWidth,
        window.innerHeight
      );

      renderer.setPixelRatio(
        Math.min(
          window.devicePixelRatio,
          2
        )
      );
    }


    // ============================================================
    // WebGLコンテキスト
    // ============================================================

    function onWebGLContextLost(event) {
      event.preventDefault();

      showError(
        "3D表示が停止しました。",
        new Error(
          [
            "WebGLコンテキストが失われました。",
            "GPUメモリまたはシステムメモリが",
            "不足している可能性があります。"
          ].join("\n")
        )
      );
    }


    function onWebGLContextRestored() {
      updateStatus(
        "3D表示を復元しました。",
        `読み込み済み：${loadedTileCount}個`,
        100
      );
    }


    // ============================================================
    // アニメーション
    // ============================================================

    function startAnimation() {
      if (animationFrameId !== null) {
        return;
      }

      animate();
    }


    function animate() {
      animationFrameId =
        requestAnimationFrame(animate);

      if (controls) {
        controls.update();
      }

      /*
        カメラと一緒に移動するライトです。
      */
      if (
        cameraLight &&
        camera
      ) {
        cameraLight.position.copy(
          camera.position
        );
      }

      if (
        renderer &&
        scene &&
        camera
      ) {
        renderer.render(
          scene,
          camera
        );
      }
    }


    // ============================================================
    // メモリ解放
    // ============================================================

    function disposeViewer() {
      if (animationFrameId !== null) {
        cancelAnimationFrame(
          animationFrameId
        );

        animationFrameId = null;
      }

      window.removeEventListener(
        "resize",
        onWindowResize
      );

      for (const tile of loadedTiles) {
        disposeObject3D(
          tile.scene
        );
      }

      loadedTiles.length = 0;

      if (controls) {
        controls.dispose();
      }

      if (renderer) {
        renderer.dispose();
      }
    }


    function disposeObject3D(rootObject) {
      if (!rootObject) {
        return;
      }

      rootObject.traverse(
        function disposeObject(object) {
          if (object.geometry) {
            object.geometry.dispose();
          }

          if (!object.material) {
            return;
          }

          const materials =
            Array.isArray(object.material)
              ? object.material
              : [object.material];

          for (const material of materials) {
            disposeMaterial(material);
          }
        }
      );
    }


    function disposeMaterial(material) {
      if (!material) {
        return;
      }

      for (const propertyName in material) {
        const propertyValue =
          material[propertyName];

        if (
          propertyValue &&
          propertyValue.isTexture
        ) {
          propertyValue.dispose();
        }
      }

      material.dispose();
    }


    // ============================================================
    // 補助関数
    // ============================================================

    function waitForNextFrame() {
      return new Promise(
        function resolveOnFrame(resolve) {
          requestAnimationFrame(resolve);
        }
      );
    }


    function formatBytes(bytes) {
      if (
        !Number.isFinite(bytes) ||
        bytes <= 0
      ) {
        return "0 B";
      }

      const units = [
        "B",
        "KB",
        "MB",
        "GB",
        "TB"
      ];

      const unitIndex =
        Math.min(
          Math.floor(
            Math.log(bytes) /
            Math.log(1024)
          ),
          units.length - 1
        );

      const value =
        bytes /
        Math.pow(
          1024,
          unitIndex
        );

      return (
        value.toFixed(
          unitIndex === 0 ? 0 : 2
        ) +
        " " +
        units[unitIndex]
      );
    }


    // ============================================================
    // 実行開始
    // ============================================================

    init();
  </script>
</body>
</html>
