//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 
/*
    ***** DISCLAIMER ***** 
    CODE A UTILISER A VOS RISQUES ET PERILS !!!!
    VOUS ETES LE SEUL ET UNIQUE RESPONSABLE DE VOS FONDS !
    L AUTEUR DE CE SMARTCONTRACT NE PEUT ÊTRE TENU RESPONSABLE DES EVENTUELLES PERTES 
    FINANCIERES LIES A L UTILISATION DE CE SMARTCONTRACT ! 
*/

// Importation de la librairie openzeppelin
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

// Definition de l interface du routeur de Hermes
interface IBaseV1Router01 is IERC20 {
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amount, bool stable);

    function swapExactTokensForTokensSimple(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

// Definition de l interface pour le staking de Tethys
interface IStaking is IERC20 {
    function enter(uint256 _amount) external returns (uint256 sharesAmount);
}


// Definition de notre contrat
contract AbitrageTethysXTethys is IERC3156FlashBorrower {
    // Definition d action a passer en temps que data 
    enum Action {
        NORMAL,
        OTHER
    }

    // variable qui va sauvegarder l adresse qui a deployer le contrat
    address deployer;
    // variable qui va sauvegarder une deadline pour les transactions
    uint256 deadline;

    // Instance ERC20 associee au contrat du token TETHYS
    IERC20 ITethys = IERC20(0x69fdb77064ec5c84FA2F21072973eB28441F43F3);
    // Instance IERC3156FlashLender associee au contrat preteur de Tethys 
    IERC3156FlashLender lender =
        IERC3156FlashLender(0x69fdb77064ec5c84FA2F21072973eB28441F43F3);

    // Instance IStaking associee au contrat de staking 
    IStaking ITethysStaking = IStaking(0x939Fe893E728f6a7A0fAAe09f236C9a6F4b67A18);

     // Instance ERC20 associee au contrat du token xTETHYS
    IERC20 IxTethys = IERC20(0x939Fe893E728f6a7A0fAAe09f236C9a6F4b67A18);

    // Instance IBaseV1Router01 associee au routerur de Hermes
    IBaseV1Router01 HermesRouter =
        IBaseV1Router01(payable(0x2d4F788fDb262a25161Aa6D6e8e1f18458da8441));

    constructor() {
        // Sauvegarde de l adresse qui a deployer le contrat
        deployer = msg.sender;
    }

    // Callback du flash Loan
    function onFlashLoan(
        address initiator, // Adresse qui a initier le flash loan
        address token, // Token emprunte
        uint256 amount, // Montant emprunte
        uint256 fee, // Interet de l emprunt
        bytes calldata data // Donnee envoye 
    ) external override returns (bytes32) {
        // On verifie que c est bien la meme addresse a qui on a fait le flash loan qui nous repond
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );

        // On verifie que c est bien le contrat qui a initialise le flash loan
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );

        uint256 amountOutMin;
        bool stable;

        // On approuve les Tethys dont on dispose pour le staking sur Staking
        ITethys.approve(address(ITethysStaking), amount);

        // On stake nos Tethys pour du XTethys
        ITethysStaking.enter(amount);

        // On recupere le montant de xTethys dont dispose le contrat
        uint256 xTethysAmount = IxTethys.balanceOf(address(this));

        // On approuve le Router Hermes pour le montant de xTethys dont dispose le contrat
        IxTethys.approve(address(HermesRouter), xTethysAmount);

        // On determine le montant de Tethys obtenu pour le montant de xTethys dans la pool de Hermes
        (amountOutMin, stable) = HermesRouter.getAmountOut(
            xTethysAmount,
            address(ITethysStaking),
            address(ITethys)
        );

        // On realise le Swap
        HermesRouter.swapExactTokensForTokensSimple(
            xTethysAmount,
            amountOutMin,
            address(IxTethys),
            address(ITethys),
            stable,
            address(this),
            deadline
        );

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function arbitrage(uint256 amount, uint256 deadline_) public {
        // On ne permet que l adresse de deploiement d executer cette fonction
        require(msg.sender == deployer, "not authorized");

        // Sauvegarde de la date limite pour les transactions
        deadline = deadline_;

        // Encodage des donnees data 
        bytes memory data = abi.encode(Action.NORMAL);

        // On recupere le montant des fees à payer pour le flashloan.  
        uint256 _fee = lender.flashFee(address(ITethys), amount);

        // Calcul du montant total à rembourser
        uint256 _repayment = amount + _fee;

        // On precise que lender peut depenser peut depensser _repayment
        ITethys.approve(address(lender), _allowance + _repayment);

        // Appel du flash loan
        lender.flashLoan(this, address(ITethys), amount, data);
    } 
 
    function withdraw() public {
        // On ne permet que l adresse de deploiement d executer cette fonction
        require(msg.sender == deployer, "not authorized");

        // On regarde la quantite de Tethys il reste sur le contrat 
        uint256 relicat = ITethys.balanceOf(address(this));

        // On transfert les Tethys du contrat a l addresse deployer
        ITethys.transfer( deployer, relicat);
    }
}
