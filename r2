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
      background: #202124;
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

      width: min(420px, calc(100vw - 32px));
      padding: 14px 16px;

      color: #ffffff;
      background: rgba(20, 20, 20, 0.85);
      border-radius: 8px;

      line-height: 1.5;
      box-shadow: 0 3px 16px rgba(0, 0, 0, 0.35);

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

  <!--
    Three.jsのモジュール読み込み設定です。
    index.htmlをWebサーバーまたはローカルサーバーから開いてください。
  -->
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
    // 基本的には、このフォルダパスだけ変更してください。
    // ============================================================

    /*
      最後には必ず「/」を付けてください。

      例：
      const TILE_FOLDER_PATH = "./models/buildingA/";

      index.htmlと同じ場所の場合：
      const TILE_FOLDER_PATH = "./";
    */
    const TILE_FOLDER_PATH = "./models/buildingA/";


    // ============================================================
    // ファイル名の設定
    // ============================================================

    /*
      以下の設定では、次のファイルを順番に読み込みます。

      タイル1.glb
      タイル2.glb
      タイル3.glb
      ...
    */
    const TILE_FILE_PREFIX = "タイル";
    const TILE_FILE_EXTENSION = ".glb";


    /*
      誤動作防止用の最大タイル番号です。

      実際のタイル数がこの数字を超える可能性がある場合は、
      数値を大きくしてください。
    */
    const MAX_TILE_COUNT = 1000;


    /*
      true：
      タイル1から順番に読み込み、
      最初に見つからなかった番号で終了します。

      false：
      タイルが見つからなくても確認を継続し、
      連続欠番数が上限に達したら終了します。

      通常はtrueを推奨します。
    */
    const STOP_AT_FIRST_MISSING_TILE = true;


    /*
      STOP_AT_FIRST_MISSING_TILEがfalseの場合に使用します。

      例えば5の場合、5番号連続でファイルが見つからなければ
      検索を終了します。
    */
    const MAX_CONSECUTIVE_MISSING_TILES = 5;


    // ============================================================
    // 表示設定
    // ============================================================

    const BACKGROUND_COLOR = 0x202124;

    /*
      床グリッドを表示する場合はtrue、
      不要な場合はfalseにします。
    */
    const SHOW_GRID = true;

    /*
      モデル全体の座標軸を表示する場合はtrueにします。
      赤：X軸
      緑：Y軸
      青：Z軸
    */
    const SHOW_AXES = false;


    // ============================================================
    // Three.jsで使用する変数
    // ============================================================

    let scene;
    let camera;
    let renderer;
    let controls;
    let gltfLoader;

    let animationFrameId = null;

    const loadedTileGroup = new THREE.Group();
    loadedTileGroup.name = "LoadedReCapTiles";

    const loadedTiles = [];

    let loadedTileCount = 0;
    let failedTileCount = 0;
    let totalLoadedBytes = 0;


    // ============================================================
    // HTML要素
    // ============================================================

    const viewerElement =
      document.getElementById("viewer");

    const statusPanel =
      document.getElementById("statusPanel");

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
      scene = new THREE.Scene();

      scene.background =
        new THREE.Color(BACKGROUND_COLOR);
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

      camera.position.set(
        10,
        10,
        10
      );
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

      /*
        glTFの色を適切に表示するための設定です。
      */
      renderer.outputColorSpace =
        THREE.SRGBColorSpace;

      renderer.toneMapping =
        THREE.ACESFilmicToneMapping;

      renderer.toneMappingExposure = 1.0;

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
      const ambientLight =
        new THREE.AmbientLight(
          0xffffff,
          1.8
        );

      scene.add(ambientLight);


      const hemisphereLight =
        new THREE.HemisphereLight(
          0xffffff,
          0x444444,
          1.2
        );

      hemisphereLight.position.set(
        0,
        100,
        0
      );

      scene.add(hemisphereLight);


      const directionalLight =
        new THREE.DirectionalLight(
          0xffffff,
          2.2
        );

      directionalLight.position.set(
        100,
        200,
        100
      );

      scene.add(directionalLight);


      const oppositeLight =
        new THREE.DirectionalLight(
          0xffffff,
          0.8
        );

      oppositeLight.position.set(
        -100,
        50,
        -100
      );

      scene.add(oppositeLight);
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
            0x444444
          );

        gridHelper.name = "GridHelper";

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

      /*
        Meshopt圧縮されたGLBにも対応します。
        圧縮されていないGLBにも影響はありません。
      */
      gltfLoader.setMeshoptDecoder(
        MeshoptDecoder
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
      totalLoadedBytes = 0;

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

          if (!gltf) {
            throw new Error(
              "GLBデータを取得できませんでした。"
            );
          }

          consecutiveMissingCount = 0;
          loadedTileCount++;

          addLoadedTileToScene(
            gltf,
            fileName,
            filePath,
            tileNumber
          );

          /*
            タイルを1個読み込むたびに画面へ反映します。
          */
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
              console.log(
                `${fileName}が存在しないため、` +
                "タイル検索を終了します。"
              );

              break;
            }


            if (
              consecutiveMissingCount >=
              MAX_CONSECUTIVE_MISSING_TILES
            ) {
              console.log(
                `${MAX_CONSECUTIVE_MISSING_TILES}件連続で` +
                "ファイルが見つからなかったため、" +
                "タイル検索を終了します。"
              );

              break;
            }

            continue;
          }


          failedTileCount++;

          console.error(
            `読み込みに失敗しました：${filePath}`,
            error
          );

          /*
            ファイル自体は存在するものの、破損などで
            読み込めなかった場合はエラーとして表示します。
          */
          appendError(
            `${fileName}の読み込みに失敗しました。`,
            error
          );

          /*
            破損ファイルがあっても、
            次の番号の確認を続けます。
          */
          continue;
        }
      }


      finishTileLoading(
        lastAttemptedTileNumber
      );
    }


    // ============================================================
    // タイルファイル名作成
    // ============================================================

    function buildTileFileName(tileNumber) {
      return (
        TILE_FILE_PREFIX +
        tileNumber +
        TILE_FILE_EXTENSION
      );
    }


    // ============================================================
    // タイルファイルパス作成
    // ============================================================

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
              progressBar.style.width =
                "100%";

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


      /*
        glTF内のメッシュ設定を整えます。
        モデル編集機能ではなく、表示品質の設定です。
      */
      tileScene.traverse(
        function configureObject(object) {
          if (!object.isMesh) {
            return;
          }

          object.frustumCulled = true;

          if (object.geometry) {
            if (
              !object.geometry.boundingBox
            ) {
              object.geometry.computeBoundingBox();
            }

            if (
              !object.geometry.boundingSphere
            ) {
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

            /*
              GLB内のテクスチャを適切な色空間で表示します。
            */
            if (material.map) {
              material.map.colorSpace =
                THREE.SRGBColorSpace;

              material.map.needsUpdate = true;
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
              "・フォルダ名の最後に/があるか",
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


      console.log(
        "すべてのタイル読み込み処理が完了しました。"
      );

      console.log(
        `読み込み成功数：${loadedTileCount}`
      );

      console.log(
        `読み込み失敗数：${failedTileCount}`
      );
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
        console.warn(
          "モデルサイズが正しくありません。"
        );

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
        new THREE.Vector3(
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


      /*
        グリッドサイズがモデルに合わない場合でも、
        モデル表示そのものには影響しません。
      */
      console.log(
        "カメラをモデル全体に合わせました。",
        {
          center,
          size,
          cameraDistance
        }
      );
    }


    // ============================================================
    // ステータス表示更新
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


    // ============================================================
    // 検索中の簡易進捗率
    // ============================================================

    function calculateSearchProgress(
      currentTileNumber
    ) {
      /*
        実際の総タイル数は事前に分からないため、
        90%を上限とした目安表示です。
      */
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
    // エラーが「ファイルなし」に近いか判定
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

      const detail =
        getErrorDetail(error);

      errorPanel.textContent =
        `${title}\n\n${detail}`;
    }


    function appendError(
      title,
      error
    ) {
      errorPanel.style.display =
        "block";

      const detail =
        getErrorDetail(error);

      const newMessage =
        `${title}\n${detail}`;

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
    // WebGLコンテキスト消失
    // ============================================================

    function onWebGLContextLost(event) {
      event.preventDefault();

      console.error(
        "WebGLコンテキストが失われました。"
      );

      showError(
        "3D表示が停止しました。",
        new Error(
          [
            "WebGLコンテキストが失われました。",
            "モデルが非常に大きく、",
            "GPUメモリまたはシステムメモリが",
            "不足している可能性があります。"
          ].join("\n")
        )
      );
    }


    function onWebGLContextRestored() {
      console.log(
        "WebGLコンテキストが復元されました。"
      );

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

        renderer.forceContextLoss();
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